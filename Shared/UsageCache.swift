import Foundation
import Security

/// The last fetched usage, written by the app and read by the widget. The widget is
/// sandboxed and can't reach the Keychain token, so it never calls the API itself.
nonisolated struct CachedUsage: Codable, Sendable {
    let limits: [PlanLimit]
    let email: String?
    let planName: String?
    let updatedAt: Date

    var sessionLimit: PlanLimit? {
        limits.first { $0.kind == "session" }
    }

    var weeklyLimits: [PlanLimit] {
        limits.filter { $0.kind != "session" }
    }

    /// Changes when anything the widget shows changes. Includes the hour of `updatedAt`
    /// so the widget's "Updated…" line can't fall more than about an hour behind.
    var widgetSignature: String {
        let rows = limits.map { limit in
            "\(limit.id)=\(Int(limit.percent.rounded()))@\(Int(limit.resetsAt?.timeIntervalSince1970 ?? 0))"
        }
        let hour = Int(updatedAt.timeIntervalSince1970 / 3600)
        return (rows + [email ?? "", planName ?? "", "\(hour)"]).joined(separator: "|")
    }
}

nonisolated enum UsageCache {
    static let widgetKind = "UsageWidget"

    static func load() -> CachedUsage? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedUsage.self, from: data)
    }

    static func save(_ usage: CachedUsage) throws {
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(usage).write(to: url, options: .atomic)
    }

    private static var fileURL: URL? {
        guard let group = appGroupIdentifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container.appending(path: "usage.json")
    }

    /// Read from the signed entitlements, where it is "<TeamID>.com.ingsoftware.ClaudeUsage",
    /// so the Team ID isn't hard-coded and follows whichever team signs the build.
    static let appGroupIdentifier: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        else { return nil }
        return (value as? [String])?.first
    }()
}
