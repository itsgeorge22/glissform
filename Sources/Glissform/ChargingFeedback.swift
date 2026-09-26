import AppKit
import MetalKit
import IOKit.ps

struct ChargingPowerTransition {
    private var previous: Bool?

    init(initial: Bool?) { previous = initial }

    mutating func update(_ external: Bool?) -> Bool {
        defer { previous = external }
        return previous == false && external == true
    }
}

struct LowBatteryTransition {
    private var previousExternal: Bool?
    private var previousPercent: Int?

    init(external: Bool?, percent: Int?) {
        previousExternal = external
        previousPercent = percent
    }

    mutating func update(external: Bool?, percent: Int?) -> Bool {
        defer {
            previousExternal = external
            previousPercent = percent
        }
        guard previousExternal == false, external == false,
              let previousPercent, let percent else { return false }
        return previousPercent > 20 && percent <= 20
    }
}

/// Watches the public power-source notification. The initial reading is only a
/// baseline: launching Glissform while plugged in never plays the effect.
final class ChargingPowerMonitor {
    private var source: CFRunLoopSource?
    private var transition: ChargingPowerTransition
    private var lowBatteryTransition: LowBatteryTransition
    private let onConnect: () -> Void
    private let onLowBattery: () -> Void

    init(onConnect: @escaping () -> Void, onLowBattery: @escaping () -> Void) {
        self.onConnect = onConnect
        self.onLowBattery = onLowBattery
        let state = Self.powerState()
        transition = ChargingPowerTransition(initial: state.external)
        lowBatteryTransition = LowBatteryTransition(external: state.external, percent: state.percent)
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<ChargingPowerMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    func refreshSilently() {
        let state = Self.powerState()
        transition = ChargingPowerTransition(initial: state.external)
        lowBatteryTransition = LowBatteryTransition(external: state.external, percent: state.percent)
    }

    private func refresh() {
        let state = Self.powerState()
        if transition.update(state.external) { onConnect() }
        if lowBatteryTransition.update(external: state.external, percent: state.percent) { onLowBattery() }
    }

    private static func powerState() -> (external: Bool?, percent: Int?) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (nil, nil) }
        let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        let external: Bool?
        switch source as String? {
        case kIOPSACPowerValue: external = true
        case kIOPSBatteryPowerValue: external = false
        default: external = nil
        }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any] else {
            return (external, nil)
        }
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue()
                    as? [String: Any],
                  details[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = details[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = details[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            return (external, min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded()))))
        }
        return (external, nil)
    }
}

@MainActor
final class ChargingFeedbackController {
    private var window: OverlayWindow?
    private var view: ChargingRippleView?
    private var renderer: ChargingRippleRenderer?
    private var cleanupTimer: Timer?
    private var activeStyle: BatteryRippleStyle?

    func play(on screen: NSScreen, style: BatteryRippleStyle) {
        stop()
        if renderer == nil { renderer = ChargingRippleRenderer(device: MTLCreateSystemDefaultDevice()) }
        guard let renderer else { return }
        let panel = OverlayWindow(contentRect: screen.frame)
        let ripple = ChargingRippleView(frame: NSRect(origin: .zero, size: screen.frame.size), device: renderer.device)
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.contentView = ripple
        renderer.start(in: ripple, style: style, reducedMotion: reducedMotion,
                       framesPerSecond: screen.maximumFramesPerSecond)
        panel.pinToCurrentSpace()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        window = panel
        view = ripple
        activeStyle = style
        let duration = reducedMotion ? ChargingRippleRenderer.reducedMotionDuration : ChargingRippleRenderer.duration
        // Close even if rendering pauses while occluded or its display disappears.
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        cleanupTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        view?.isPaused = true
        view?.delegate = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        view = nil
        activeStyle = nil
    }

    func stop(if style: BatteryRippleStyle) {
        if activeStyle == style { stop() }
    }
}
