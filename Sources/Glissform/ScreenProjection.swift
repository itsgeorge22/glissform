import Foundation

/// Dimensions are in screen heights, in the reference screenshot's coordinate
/// system. This is a fixed seated viewpoint, not a measured/head-tracked camera.
enum ScreenProjection {
    static let eyeDistance: Float = 4
    static let eyeHeight: Float = 1.1

    static func foldRadians(lidAngle: Double, referenceAngle: Double) -> Float {
        Float(max(0, min(180, referenceAngle) - max(0, lidAngle)) * .pi / 180)
    }

    /// Preserve almost one-to-one rotation at the start, then softly limit
    /// vertical enlargement without an early/late handoff. The fourth-power
    /// cap keeps the initial response strong; its positive 22% residual keeps
    /// the image moving late. The top source sample stays above 43% even at
    /// the largest supported 130° fold.
    static func imageRadians(for fold: Float) -> Float {
        let scale = Float(34 * Double.pi / 180)
        let residual: Float = 0.22
        let positiveFold = max(0, fold)
        let normalized = positiveFold / scale
        let square = normalized * normalized
        let softCap = positiveFold / sqrt(sqrt(1 + square * square))
        return residual * positiveFold + (1 - residual) * softCap
    }

    /// Begin narrowing the upper edge immediately. This nearly matches the
    /// projected top source height from the middle onward, while allowing a
    /// stronger first response than the source-height curve alone provides.
    /// The fixed angular slope prevents short low-angle folds from squeezing
    /// all the way to the same final width as a full fold.
    static func topWidth(for fold: Float) -> Float {
        let longestFold = Float(130 * Double.pi / 180)
        let progress = min(1, max(0, fold / longestFold))
        return 1 - 0.58 * progress
    }
}
