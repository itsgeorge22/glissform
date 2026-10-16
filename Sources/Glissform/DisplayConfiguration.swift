import CoreGraphics

/// Physical/virtual online displays, including mirror followers omitted by NSScreen.
/// Reading this configuration never changes display modes, window positions or sleep.
struct DisplayConfiguration: Equatable {
    struct Display: Equatable {
        let id: CGDirectDisplayID
        let isBuiltIn: Bool
        let isInMirrorSet: Bool
        let mirrorsDisplay: CGDirectDisplayID
        let bounds: CGRect
        let pixelWidth: Int
        let pixelHeight: Int
        let rotation: Double
    }

    enum PauseReason: String {
        case unavailable = "Waiting for display information"
        case mirroring = "Paused while your MacBook display is mirrored"
        case externalDisplay = "Paused while an external display is connected"
        case builtInUnavailable = "Waiting for the MacBook display"
    }

    let displays: [Display]
    let builtInIsActive: Bool
    var isValid = true

    var builtInDisplay: Display? { displays.first(where: \.isBuiltIn) }
    var hasExternalDisplay: Bool { displays.contains { !$0.isBuiltIn } }

    func pauseReason(supportEnabled: Bool) -> PauseReason? {
        guard isValid else { return .unavailable }
        if let builtIn = builtInDisplay,
           builtIn.isInMirrorSet || builtIn.mirrorsDisplay != kCGNullDirectDisplay
            || displays.contains(where: { $0.mirrorsDisplay == builtIn.id }) {
            return .mirroring
        }
        if hasExternalDisplay && !supportEnabled { return .externalDisplay }
        guard builtInDisplay != nil, builtInIsActive else { return .builtInUnavailable }
        return nil
    }

    /// Sleep availability is separate from topology, so a redundant sleep/wake
    /// notification does not invalidate an otherwise eligible laptop-only image.
    func hasSameTopology(as other: Self) -> Bool {
        isValid && other.isValid && displays == other.displays
    }

    static func current() -> Self {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
            return Self(displays: [], builtInIsActive: false, isValid: false)
        }
        // Leave room for a display connected between these two calls.
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count) + 8)
        let capacity = UInt32(ids.count)
        guard CGGetOnlineDisplayList(capacity, &ids, &count) == .success,
              count < capacity else {
            return Self(displays: [], builtInIsActive: false, isValid: false)
        }
        let displays = ids.prefix(Int(count)).map { id in
            let mode = CGDisplayCopyDisplayMode(id)
            return Display(id: id, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                           isInMirrorSet: CGDisplayIsInMirrorSet(id) != 0,
                           mirrorsDisplay: CGDisplayMirrorsDisplay(id),
                           bounds: CGDisplayBounds(id),
                           pixelWidth: mode?.pixelWidth ?? 0,
                           pixelHeight: mode?.pixelHeight ?? 0,
                           rotation: CGDisplayRotation(id))
        }.sorted { $0.id < $1.id }
        let active = displays.first(where: \.isBuiltIn).map {
            CGDisplayIsActive($0.id) != 0 && CGDisplayIsAsleep($0.id) == 0
        } ?? false
        return Self(displays: displays, builtInIsActive: active)
    }
}
