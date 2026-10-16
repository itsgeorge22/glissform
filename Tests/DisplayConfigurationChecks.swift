import CoreGraphics

@main struct DisplayConfigurationChecks {
    static func main() {
        func display(_ id: UInt32, builtIn: Bool = false, mirrored: Bool = false,
                     source: UInt32 = 0, x: CGFloat = 0, width: Int = 2000) -> DisplayConfiguration.Display {
            .init(id: id, isBuiltIn: builtIn, isInMirrorSet: mirrored, mirrorsDisplay: source,
                  bounds: CGRect(x: x, y: 0, width: 1000, height: 700),
                  pixelWidth: width, pixelHeight: 1400, rotation: 0)
        }
        let laptop = display(1, builtIn: true)
        let monitor = display(2, x: 1000)
        let standalone = DisplayConfiguration(displays: [laptop], builtInIsActive: true)
        let extended = DisplayConfiguration(displays: [laptop, monitor], builtInIsActive: true)
        for support in [false, true] {
            precondition(standalone.pauseReason(supportEnabled: support) == nil)
            precondition(extended.pauseReason(supportEnabled: support) == (support ? nil : .externalDisplay))
            let mirrorSource = DisplayConfiguration(displays: [display(1, builtIn: true, mirrored: true),
                display(2, mirrored: true, source: 1)], builtInIsActive: true)
            let mirrorFollower = DisplayConfiguration(displays: [display(1, builtIn: true, mirrored: true, source: 2),
                display(2, mirrored: true)], builtInIsActive: false)
            precondition(mirrorSource.pauseReason(supportEnabled: support) == .mirroring)
            precondition(mirrorFollower.pauseReason(supportEnabled: support) == .mirroring)
            let followerOnlyHint = DisplayConfiguration(displays: [laptop, display(2, source: 1)], builtInIsActive: true)
            precondition(followerOnlyHint.pauseReason(supportEnabled: support) == .mirroring)
        }
        let externalMirrorOnly = DisplayConfiguration(displays: [laptop,
            display(2, mirrored: true), display(3, mirrored: true, source: 2)], builtInIsActive: true)
        precondition(externalMirrorOnly.pauseReason(supportEnabled: true) == nil,
                     "Mirroring two external displays must not pause an independent MacBook display")
        let closed = DisplayConfiguration(displays: [monitor], builtInIsActive: false)
        precondition(closed.pauseReason(supportEnabled: true) == .builtInUnavailable)
        precondition(closed.pauseReason(supportEnabled: false) == .externalDisplay)
        precondition(DisplayConfiguration(displays: extended.displays, builtInIsActive: false)
            .pauseReason(supportEnabled: true) == .builtInUnavailable)
        precondition(DisplayConfiguration(displays: [], builtInIsActive: false, isValid: false)
            .pauseReason(supportEnabled: true) == .unavailable)
        print("PASS: standalone, extended, both mirror roles, external-only mirroring, closed lid and unavailable display information")

        precondition(!standalone.hasSameTopology(as: extended))
        precondition(!extended.hasSameTopology(as: .init(displays: [laptop, display(2, x: -1000)], builtInIsActive: true)))
        precondition(!extended.hasSameTopology(as: .init(displays: [laptop, display(2, width: 3000)], builtInIsActive: true)))
        precondition(!extended.hasSameTopology(as: .init(displays: [laptop, display(3, x: 1000)], builtInIsActive: true)))
        precondition(standalone.hasSameTopology(as: .init(displays: [laptop], builtInIsActive: false)),
                     "Sleep alone must not invalidate the laptop-only wake image")
        print("PASS: display identity, arrangement and resolution invalidate topology; sleep availability is independent")
    }
}
