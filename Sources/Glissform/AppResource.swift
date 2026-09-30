import Foundation

enum AppResource {
    static func url(_ name: String, extension fileExtension: String, subdirectory: String) -> URL? {
        let bundleName = "Glissform_Glissform.bundle"
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
            .compactMap { $0 }
        for root in roots {
            for base in [root.appendingPathComponent(bundleName).appendingPathComponent("Contents/Resources"),
                         root.appendingPathComponent(bundleName)] {
                let url = base.appendingPathComponent(subdirectory).appendingPathComponent("\(name).\(fileExtension)")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }
}
