import Foundation

enum AppVersion {
    static var displayVersion: String {
        bundleString(for: "CFBundleShortVersionString", fallback: "1.0.0625")
    }

    static var buildTime: String {
        bundleString(for: "SnapMarkBuildTime", fallback: "000000")
    }

    static var aboutVersionText: String {
        "V\(displayVersion) \(buildTime)"
    }

    private static func bundleString(for key: String, fallback: String) -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        return fallback
    }
}
