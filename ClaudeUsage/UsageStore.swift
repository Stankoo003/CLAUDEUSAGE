import Foundation
import Observation
import OSLog
import WidgetKit

private let logger = Logger(subsystem: "com.ingsoftware.ClaudeUsage", category: "UsageStore")

@Observable
final class UsageStore {
    enum Status: Equatable {
        case loading
        case ready
        /// No usable Claude Code sign-in; the message says what to do.
        case signedOut(String)
        case failed(String)
    }

    private(set) var status: Status = .loading
    private(set) var limits: [PlanLimit] = []
    private(set) var email: String?
    private(set) var planName: String?
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false

    /// The endpoint is rate limited (Claude Code's own `/usage` hits that too), so poll gently.
    static let pollInterval: Duration = .seconds(5 * 60)
    static let retryInterval: Duration = .seconds(2 * 60)
    static let rateLimitedInterval: Duration = .seconds(15 * 60)

    private var credentials: ClaudeCredentials?
    private var pollTask: Task<Void, Never>?
    private var rateLimitedUntil: Date?

    var sessionLimit: PlanLimit? {
        limits.first { $0.kind == "session" }
    }

    func start() {
        guard pollTask == nil else { return }
        email = ClaudeAccount.load().email
        pollTask = Task {
            while !Task.isCancelled {
                guard let delay = await refresh() else { return }
                try? await Task.sleep(for: delay)
            }
        }
    }

    /// Fetches usage once. Returns the delay before the next automatic refresh,
    /// or nil when retrying on its own would only repeat a Keychain prompt the user declined.
    @discardableResult
    func refresh() async -> Duration? {
        if let rateLimitedUntil, rateLimitedUntil > .now {
            return .seconds(rateLimitedUntil.timeIntervalSinceNow)
        }
        guard !isRefreshing else { return Self.pollInterval }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let credentials = try await currentCredentials()
            let snapshot = try await UsageAPI.fetch(accessToken: credentials.accessToken)
            limits = snapshot.limits
            lastUpdated = .now
            status = .ready
            publishToWidget()
            return Self.pollInterval
        } catch UsageAPIError.unauthorized {
            // Claude Code may have rotated the token since we read it; read it again next time.
            credentials = nil
            status = .signedOut(UsageAPIError.unauthorized.localizedDescription)
            return Self.retryInterval
        } catch UsageAPIError.rateLimited(let retryAfter) {
            let wait = retryAfter.map { Duration.seconds($0) } ?? Self.rateLimitedInterval
            rateLimitedUntil = .now.addingTimeInterval(TimeInterval(wait.components.seconds))
            status = .failed(UsageAPIError.rateLimited(retryAfter: retryAfter).localizedDescription)
            return wait
        } catch CredentialsError.accessDenied {
            status = .signedOut(CredentialsError.accessDenied.localizedDescription)
            return nil
        } catch let error as CredentialsError {
            status = .signedOut(error.localizedDescription)
            return Self.retryInterval
        } catch {
            status = .failed(error.localizedDescription)
            return Self.retryInterval
        }
    }

    /// Restarts polling after the user fixed a sign-in or Keychain problem.
    func retry() {
        pollTask?.cancel()
        pollTask = nil
        start()
    }

    /// Writes the latest usage for the widget. Widget reloads are budgeted by macOS, so the
    /// timeline is only reloaded when something the widget shows has changed.
    private func publishToWidget() {
        let previous = UsageCache.load()
        let usage = CachedUsage(limits: limits, email: email, planName: planName, updatedAt: lastUpdated ?? .now)
        do {
            try UsageCache.save(usage)
        } catch {
            let group = UsageCache.appGroupIdentifier ?? "none"
            logger.error("Widget cache not written (app group: \(group, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return
        }
        if previous.map({ $0.widgetSignature != usage.widgetSignature }) ?? true {
            WidgetCenter.shared.reloadTimelines(ofKind: UsageCache.widgetKind)
        }
    }

    private func currentCredentials() async throws -> ClaudeCredentials {
        if let credentials, !credentials.isExpired {
            return credentials
        }
        let loaded = try await Task.detached { try ClaudeCredentials.loadFromKeychain() }.value
        planName = loaded.planName
        // Only Claude Code renews the token; an expired one means waiting for it to do so.
        guard !loaded.isExpired else { throw CredentialsError.expired }
        credentials = loaded
        return loaded
    }
}

#if DEBUG
extension UsageStore {
    static var preview: UsageStore {
        let store = UsageStore()
        store.email = "you@example.com"
        store.planName = "Max 5x"
        store.lastUpdated = .now.addingTimeInterval(-90)
        store.status = .ready
        store.limits = [
            PlanLimit(kind: "session", group: "session", percent: 1, severity: "normal",
                      resetsAt: .now.addingTimeInterval(4 * 3600 + 40 * 60), scope: nil, isActive: false),
            PlanLimit(kind: "weekly_all", group: "weekly", percent: 39, severity: "normal",
                      resetsAt: .now.addingTimeInterval(2 * 86400 + 7 * 3600), scope: nil, isActive: false),
            PlanLimit(kind: "weekly_scoped", group: "weekly", percent: 66, severity: "normal",
                      resetsAt: .now.addingTimeInterval(2 * 86400 + 7 * 3600),
                      scope: .init(model: .init(id: nil, displayName: "Fable")), isActive: true),
        ]
        return store
    }
}
#endif
