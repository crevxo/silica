import Foundation

/// Sparkle is dormant in development builds. Set `SUFeedURL` and `SUPublicEDKey`
/// in the generated Info.plist when a release feed and signing key are ready.
enum UpdateConfiguration {
    private static func value(for key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isConfigured: Bool {
        guard let url = URL(string: value(for: "SUFeedURL")) else { return false }
        return url.scheme == "https" && !value(for: "SUPublicEDKey").isEmpty
    }

    static var version: String {
        let bundled = value(for: "CFBundleShortVersionString")
        return bundled.isEmpty ? "1.0.0" : bundled
    }
}
