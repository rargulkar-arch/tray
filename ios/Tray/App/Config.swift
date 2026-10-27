import Foundation

/// Backend coordinates, injected at build time from `Secrets.xcconfig`.
enum Config {
    static let host: String = string("SUPABASE_HOST")
    static let anonKey: String = string("SUPABASE_ANON_KEY")

    static var baseURL: URL { URL(string: "https://\(host)")! }

    /// True once `Secrets.xcconfig` has been filled in with a real project.
    static var isConfigured: Bool {
        !host.isEmpty && !host.hasPrefix("YOUR-") && !anonKey.isEmpty && !anonKey.hasPrefix("YOUR-")
    }

    /// The background refresh task that lets Tray raise notifications while closed.
    static let refreshTaskID = "app.tray.refresh"

    private static func string(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
