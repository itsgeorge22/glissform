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
}
