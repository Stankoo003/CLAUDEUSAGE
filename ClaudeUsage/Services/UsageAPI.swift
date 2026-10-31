import Foundation

/// The endpoint Claude Code's `/usage` screen reads. Undocumented, so it may change.
nonisolated enum UsageAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch(accessToken: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return try UsageSnapshot.decode(from: data)
        case 401, 403:
            throw UsageAPIError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw UsageAPIError.rateLimited(retryAfter: retryAfter)
        default:
            throw UsageAPIError.http(http.statusCode)
        }
    }
}

nonisolated enum UsageAPIError: LocalizedError {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Claude Code's sign-in was rejected. Open Claude Code to renew it."
        case .rateLimited: "Usage endpoint is rate limited."
        case .http(let code): "Usage request failed (HTTP \(code))."
        case .invalidResponse: "Unexpected response from the usage endpoint."
        }
    }
}
