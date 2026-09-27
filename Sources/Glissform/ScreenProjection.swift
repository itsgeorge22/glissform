import Foundation

/// Dimensions are in screen heights, in the reference screenshot's coordinate
/// system. This is a fixed seated viewpoint, not a measured/head-tracked camera.
enum ScreenProjection {
    static let eyeDistance: Float = 4
    static let eyeHeight: Float = 1.1

    static func foldRadians(lidAngle: Double, referenceAngle: Double) -> Float {
        Float(max(0, min(180, referenceAngle) - max(0, lidAngle)) * .pi / 180)
    }

    /// One continuous perspective response replaces the early/late angle
    /// handoff. The 96° scale keeps the top source sample near 55% after a
    /// typical 101° fold and above 43% even at the largest supported 130°
    /// fold. The derivative stays positive, so the image keeps moving late.
    static func imageRadians(for fold: Float) -> Float {
        let scale = Float(96 * Double.pi / 180)
        let positiveFold = max(0, fold)
        return positiveFold * scale / (scale + positiveFold)
    }

    /// Match the visible top width to the top row's source-plane height under
    /// that same projection. Both dimensions then change together, without a
    /// separate taper curve or excessive squeezing from a low start angle.
    static func topWidth(for fold: Float) -> Float {
        let angle = imageRadians(for: fold)
        let depth = sin(angle)
        return (eyeDistance * cos(angle) - eyeHeight * depth) / (eyeDistance - depth)
    }
}
