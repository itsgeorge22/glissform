import Foundation

/// Dimensions are in screen heights, in the reference screenshot's coordinate
/// system. This is a fixed seated viewpoint, not a measured/head-tracked camera.
enum ScreenProjection {
    static let eyeDistance: Float = 4
    static let eyeHeight: Float = 1.1

    static func foldRadians(lidAngle: Double, referenceAngle: Double) -> Float {
        Float(max(0, min(180, referenceAngle) - max(0, lidAngle)) * .pi / 180)
    }
}
