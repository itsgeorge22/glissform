enum BlurStrength: String, CaseIterable {
    case high, regular, subtle

    static let defaultStrength: Self = .regular
    var title: String { rawValue.capitalized }

    // High preserves the existing material. Both blur passes use this scale.
    var scale: Float {
        switch self {
        case .high: return 1
        case .regular: return 0.65
        case .subtle: return 0.20
        }
    }

    func scale(at closureFraction: Float) -> Float {
        guard self == .regular else { return scale }
        // Keep the start of the default preset clearer, then recover its
        // established strength before the lid reaches the deep fold.
        let t = min(1, max(0, closureFraction / 0.75))
        let ramp = t * t * (3 - 2 * t)
        return scale * (0.60 + 0.40 * ramp)
    }
}
