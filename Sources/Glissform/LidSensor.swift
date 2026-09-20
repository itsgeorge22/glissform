import Foundation
import IOKit.hid
import os

/// Read-only access to Apple's lid-angle HID feature report. The HID API is public;
/// this device's usage/report layout is undocumented and may change with macOS.
/// Protocol reference: github.com/samhenrigold/LidAngleSensor (HardwareCompat.swift).
/// Lifecycle methods are called on the main thread; device I/O runs on a serial queue.
final class LidSensor {
    private let queue = DispatchQueue(label: "app.glissform.lid-sensor", qos: .userInitiated)
    private var worker: Worker?
    private var generation = UUID()

    func start(onReading: @escaping (Double, Double) -> Void, onStatus: @escaping (String) -> Void) {
        precondition(Thread.isMainThread)
        stop()
        let token = generation
        let worker = Worker()
        self.worker = worker
        queue.async { [weak self] in
            worker.begin(on: self?.queue, reading: { angle, acquiredAt in
                DispatchQueue.main.async { [weak self] in
                    guard self?.generation == token else { return }
                    onReading(angle, acquiredAt)
                }
            }, status: { status in
                DispatchQueue.main.async { [weak self] in
                    guard self?.generation == token else { return }
                    onStatus(status)
                }
            })
        }
    }

    /// Higher polling is limited to an active gesture; it does not change the
    /// sensor's whole-degree resolution or perform any additional screen capture.
    func setActivePolling(_ active: Bool) {
        precondition(Thread.isMainThread)
        guard let worker else { return }
        queue.async { worker.setActivePolling(active) }
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
        private var activePolling = false
        private let diagnosticsEnabled = ProcessInfo.processInfo.environment["GLISSFORM_MOTION_DIAGNOSTICS"] == "1"
        private let logger = Logger(subsystem: "com.george.glissform.mvp", category: "MotionTiming")
        private var diagnosticStart = ProcessInfo.processInfo.systemUptime
        private var reads = 0
        private var distinctReadings = 0
        private var previousAngle: Double?
        private var totalReadMilliseconds: Double = 0
        private var maximumReadMilliseconds: Double = 0

        func begin(on queue: DispatchQueue?, reading: @escaping (Double, Double) -> Void,
                   status: @escaping (String) -> Void) {
            guard let queue else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            self.timer = timer
            scheduleTimer()
            timer.setEventHandler { [weak self] in
                self?.tick(reading: reading, status: status)
            }
            timer.resume()
        }

        func setActivePolling(_ active: Bool) {
            guard active != activePolling else { return }
            logDiagnostics(force: true)
            activePolling = active
            scheduleTimer()
        }

        private func scheduleTimer() {
            timer?.schedule(deadline: .now(),
                            repeating: .nanoseconds(activePolling ? 16_666_667 : 33_333_333),
                            leeway: .milliseconds(activePolling ? 1 : 3))
        }

        func end() {
            logDiagnostics(force: true)
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
            connection = nil
        }

        private func tick(reading: (Double, Double) -> Void, status: (String) -> Void) {
            let now = ProcessInfo.processInfo.systemUptime
            guard now >= retryAt else { return }
            do {
                if connection == nil {
                    let candidate = Connection()
                    try candidate.open()
                    connection = candidate
                }
                guard let connection else { return }
                let readStarted = ProcessInfo.processInfo.systemUptime
                let angle = try connection.read()
                // The HID report has no device timestamp. Preserve host read
                // completion time before delivery can wait on the main queue.
                let acquiredAt = ProcessInfo.processInfo.systemUptime
                if diagnosticsEnabled {
                    reads += 1
                    if previousAngle != angle { distinctReadings += 1 }
                    previousAngle = angle
                    let milliseconds = (acquiredAt - readStarted) * 1000
                    totalReadMilliseconds += milliseconds
                    maximumReadMilliseconds = max(maximumReadMilliseconds, milliseconds)
                    logDiagnostics(force: false)
                }
                retryDelay = 1
                report("Lid sensor ready", to: status)
                reading(angle, acquiredAt)
            } catch {
                connection = nil
                retryAt = now + retryDelay
                retryDelay = min(retryDelay * 2, 8)
                report("Lid sensor unavailable — retrying: \(error.localizedDescription)", to: status)
            }
        }

        private func logDiagnostics(force: Bool) {
            guard diagnosticsEnabled else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let duration = now - diagnosticStart
            guard reads > 0, force || duration >= 2 else { return }
            let mean = totalReadMilliseconds / Double(reads)
            logger.debug("sensor active=\(self.activePolling), seconds=\(duration), reads=\(self.reads), distinct=\(self.distinctReadings), meanReadMs=\(mean), maxReadMs=\(self.maximumReadMilliseconds)")
            diagnosticStart = now
            reads = 0
            distinctReadings = 0
            totalReadMilliseconds = 0
            maximumReadMilliseconds = 0
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
