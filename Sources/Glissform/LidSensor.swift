import Foundation
import IOKit.hid

/// Read-only access to Apple's lid-angle HID feature report. The HID API is public;
/// this device's usage/report layout is undocumented and may change with macOS.
/// Protocol reference: github.com/samhenrigold/LidAngleSensor (HardwareCompat.swift).
/// Lifecycle methods are called on the main thread; device I/O runs on a serial queue.
final class LidSensor {
    private let queue = DispatchQueue(label: "app.glissform.lid-sensor", qos: .userInitiated)
    private var worker: Worker?
    private var generation = UUID()

    func start(onReading: @escaping (Double) -> Void, onStatus: @escaping (String) -> Void) {
        precondition(Thread.isMainThread)
        stop()
        let token = generation
        let worker = Worker()
        self.worker = worker
        queue.async { [weak self] in
            worker.begin(on: self?.queue, reading: { angle in
                DispatchQueue.main.async { [weak self] in
                    guard self?.generation == token else { return }
                    onReading(angle)
                }
            }, status: { status in
                DispatchQueue.main.async { [weak self] in
                    guard self?.generation == token else { return }
                    onStatus(status)
                }
            })
        }
    }

    func stop() {
        precondition(Thread.isMainThread)
        generation = UUID()
        if let worker {
            queue.async { worker.end() }
            self.worker = nil
        }
    }

    deinit {
        if let worker { queue.async { worker.end() } }
    }

    /// Synchronous diagnostic for --probe only. Never call from a UI event handler.
    static func probe() -> String {
        let connection = Connection()
        do {
            try connection.open()
            let angle = try connection.read()
            return "Lid sensor detected: Apple HID 05ac:8104, usage 0020:008a; angle \(Int(angle))°"
        } catch {
            return "Lid sensor unavailable: \(error.localizedDescription)"
        }
    }

    private final class Worker {
        private var timer: DispatchSourceTimer?
        private var connection: Connection?
        private var retryAt: TimeInterval = 0
        private var retryDelay: TimeInterval = 1
        private var lastStatus = ""

        func begin(on queue: DispatchQueue?, reading: @escaping (Double) -> Void,
                   status: @escaping (String) -> Void) {
            guard let queue else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            self.timer = timer
            timer.schedule(deadline: .now(), repeating: .nanoseconds(33_333_333),
                           leeway: .milliseconds(3))
            timer.setEventHandler { [weak self] in
                self?.tick(reading: reading, status: status)
            }
            timer.resume()
        }

        func end() {
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
            connection = nil
        }

        private func tick(reading: (Double) -> Void, status: (String) -> Void) {
            let now = ProcessInfo.processInfo.systemUptime
            guard now >= retryAt else { return }
            do {
                if connection == nil {
                    let candidate = Connection()
                    try candidate.open()
                    connection = candidate
                }
                guard let connection else { return }
                let angle = try connection.read()
                retryDelay = 1
                report("Lid sensor ready", to: status)
                reading(angle)
            } catch {
                connection = nil
                retryAt = now + retryDelay
                retryDelay = min(retryDelay * 2, 8)
                report("Lid sensor unavailable — retrying: \(error.localizedDescription)", to: status)
            }
        }

        private func report(_ message: String, to callback: (String) -> Void) {
            guard message != lastStatus else { return }
            lastStatus = message
            callback(message)
        }
    }

    private final class Connection {
        private var device: IOHIDDevice?
        private var manager: IOHIDManager?
        private static let options = IOOptionBits(kIOHIDOptionsTypeNone)

        func open() throws {
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, Self.options)
            // A narrow match avoids inspecting or requesting access to keyboard input.
            IOHIDManagerSetDeviceMatching(manager, [
                kIOHIDVendorIDKey: 0x05AC,
                kIOHIDProductIDKey: 0x8104,
                kIOHIDDeviceUsagePageKey: 0x0020,
                kIOHIDDeviceUsageKey: 0x008A,
            ] as CFDictionary)
            let result = IOHIDManagerOpen(manager, Self.options)
            guard result == kIOReturnSuccess else {
                throw SensorError("Cannot open HID manager (\(result))")
            }
            self.manager = manager
            guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
                  !devices.isEmpty else {
                throw SensorError("No supported lid-angle HID interface found")
            }
            var lastFailure: Error = SensorError("Cannot open lid sensor")
            for candidate in devices {
                let result = IOHIDDeviceOpen(candidate, Self.options)
                guard result == kIOReturnSuccess else {
                    lastFailure = SensorError("Cannot open lid sensor (\(result))")
                    continue
                }
                device = candidate
                do {
                    _ = try read()
                    return
                } catch {
                    lastFailure = error
                    IOHIDDeviceClose(candidate, Self.options)
                    device = nil
                }
            }
            throw lastFailure
        }

        func read() throws -> Double {
            guard let device else { throw SensorError("Sensor is disconnected") }
            var bytes = [UInt8](repeating: 0, count: 8)
            var count = bytes.count
            let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &count)
            guard result == kIOReturnSuccess else {
                throw SensorError("HID report failed (\(result))")
            }
            guard count >= 3 else { throw SensorError("Incomplete lid-angle report") }
            // Feature report 1 stores whole degrees as little-endian bytes 1 and 2.
            let degrees = Int(bytes[1]) + (Int(bytes[2]) << 8)
            guard (0...180).contains(degrees) else {
                throw SensorError("Invalid lid angle: \(degrees)")
            }
            return Double(degrees)
        }

        deinit {
            if let device { IOHIDDeviceClose(device, Self.options) }
            if let manager { IOHIDManagerClose(manager, Self.options) }
        }
    }

    private struct SensorError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
