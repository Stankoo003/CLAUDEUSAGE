import Foundation

/// Response of `GET /api/oauth/usage`. The endpoint is undocumented, so only the
/// `limits` array is decoded and any entry that fails to decode is skipped.
nonisolated struct UsageSnapshot: Decodable, Sendable {
    let limits: [PlanLimit]

    init(limits: [PlanLimit]) {
        self.limits = limits
    }

    private enum CodingKeys: String, CodingKey {
        case limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decodeIfPresent([Lossy<PlanLimit>].self, forKey: .limits) ?? []
        limits = entries.compactMap(\.value)
    }

    static func decode(from data: Data) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { try parseDate($0) }
        return try decoder.decode(UsageSnapshot.self, from: data)
    }

    private static func parseDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        // The API sends microseconds ("…T23:40:00.435501+00:00"), which ISO8601DateFormatter rejects.
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        guard let date = ISO8601DateFormatter().date(from: trimmed) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return date
    }
}

/// Codable so the app can cache it for the widget.
nonisolated struct PlanLimit: Codable, Sendable, Identifiable {
    /// `session`, `weekly_all`, `weekly_scoped`, or a kind this app doesn't know yet.
    let kind: String
    let group: String?
    let percent: Double
    let severity: String?
    let resetsAt: Date?
    let scope: Scope?
    let isActive: Bool?

    nonisolated struct Scope: Codable, Sendable {
        let model: Model?
    }

    nonisolated struct Model: Codable, Sendable {
        let id: String?
        let displayName: String?
    }

    var id: String {
        [kind, scopeName].compactMap { $0 }.joined(separator: ":")
    }

    var scopeName: String? {
        scope?.model?.displayName ?? scope?.model?.id
    }

    var title: String {
        switch kind {
        case "session": "Current session"
        case "weekly_all": "This week · All models"
        case "weekly_scoped": "This week · \(scopeName ?? "Scoped")"
        default: kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// For tight layouts such as the medium widget.
    var shortTitle: String {
        switch kind {
        case "session": "Session"
        case "weekly_all": "Week · All"
        case "weekly_scoped": "Week · \(scopeName ?? "Scoped")"
        default: title
        }
    }

    /// 0...1, for progress bars.
    var fraction: Double {
        min(max(percent / 100, 0), 1)
    }

    var isReached: Bool {
        percent >= 100
    }

    /// "Resets in 2 h 14 min" within a day, otherwise "Resets Thu 09:00".
    /// `compact` gives "Resets 2 h 14 m" for the small widget.
    func resetText(now: Date, compact: Bool = false) -> String {
        guard let resetsAt else { return "" }
        let remaining = Int(resetsAt.timeIntervalSince(now))
        if remaining <= 0 { return "Resetting…" }
        let prefix = isReached ? "Limit reached · resets" : "Resets"
        if remaining < 24 * 3600 {
            let hours = remaining / 3600
            let minutes = remaining % 3600 / 60
            let minuteUnit = compact ? "m" : "min"
            let duration = hours > 0 ? "\(hours) h \(minutes) \(minuteUnit)" : "\(minutes) \(minuteUnit)"
            return compact ? "\(prefix) \(duration)" : "\(prefix) in \(duration)"
        }
        return "\(prefix) " + resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// Decodes `T` and yields nil instead of failing the whole array.
nonisolated private struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
