import Foundation
import Security

/// The OAuth token Claude Code keeps in the login Keychain. This app only reads it:
/// refreshing it here would rotate the refresh token and sign Claude Code out.
nonisolated struct ClaudeCredentials: Sendable {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?
    let rateLimitTier: String?

    var isExpired: Bool {
        expiresAt.map { $0 <= .now } ?? false
    }

    /// "Max 5x", "Max 20x", "Pro", …
    var planName: String? {
        let tier = rateLimitTier ?? ""
        if tier.contains("max_20x") { return "Max 20x" }
        if tier.contains("max_5x") { return "Max 5x" }
        guard let subscriptionType, !subscriptionType.isEmpty else { return nil }
        return subscriptionType.prefix(1).uppercased() + subscriptionType.dropFirst()
    }

    static let keychainService = "Claude Code-credentials"

    /// Blocks while macOS shows the Keychain access prompt, so call it off the main actor.
    static func loadFromKeychain() throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw CredentialsError.notFound
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw CredentialsError.accessDenied
        default:
            throw CredentialsError.keychain(status)
        }

        guard let data = item as? Data,
              let oauth = try? JSONDecoder().decode(KeychainPayload.self, from: data).claudeAiOauth
        else {
            throw CredentialsError.malformed
        }

        return ClaudeCredentials(
            accessToken: oauth.accessToken,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            subscriptionType: oauth.subscriptionType,
            rateLimitTier: oauth.rateLimitTier
        )
    }
}

nonisolated private struct KeychainPayload: Decodable {
    let claudeAiOauth: OAuth?

    struct OAuth: Decodable {
        let accessToken: String
        /// Milliseconds since 1970.
        let expiresAt: Double?
        let subscriptionType: String?
        let rateLimitTier: String?
    }
}

nonisolated enum CredentialsError: LocalizedError {
    case notFound
    case accessDenied
    case expired
    case malformed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notFound: "Claude Code isn't signed in on this Mac."
        case .accessDenied: "Keychain access was denied."
        case .expired: "Claude Code's sign-in has expired. Open Claude Code to renew it."
        case .malformed: "Couldn't read Claude Code's credentials."
        case .keychain(let status): "Keychain error \(status)."
        }
    }
}

/// Account details Claude Code caches in `~/.claude.json`.
nonisolated struct ClaudeAccount: Sendable {
    let email: String?

    static func load() -> ClaudeAccount {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(ConfigFile.self, from: data)
        else {
            return ClaudeAccount(email: nil)
        }
        return ClaudeAccount(email: config.oauthAccount?.emailAddress)
    }

    private struct ConfigFile: Decodable {
        let oauthAccount: OAuthAccount?

        struct OAuthAccount: Decodable {
            let emailAddress: String?
        }
    }
}
