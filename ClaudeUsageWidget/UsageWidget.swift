import SwiftUI
import WidgetKit

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: UsageCache.widgetKind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Claude usage")
        .description("Your Claude plan limits: current session and this week.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    /// nil until the app has fetched usage at least once.
    let usage: CachedUsage?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, usage: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let usage = UsageCache.load() ?? (context.isPreview ? .sample : nil)
        completion(UsageEntry(date: .now, usage: usage))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let usage = UsageCache.load()
        let now = Date.now
        // The same data re-rendered every 15 minutes for 4 hours, so countdowns and
        // "Updated…" advance without spending reloads. The app reloads on new data.
        let entries = (0..<16).map { step in
            UsageEntry(date: now.addingTimeInterval(Double(step) * 15 * 60), usage: usage)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Views

struct UsageWidgetView: View {
    let entry: UsageEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let usage = entry.usage {
            switch family {
            case .systemSmall:
                SmallUsageView(usage: usage, now: entry.date)
            case .systemMedium:
                MediumUsageView(usage: usage, now: entry.date)
            default:
                LargeUsageView(usage: usage, now: entry.date)
            }
        } else {
            NotConnectedView()
        }
    }
}

/// Percentage to show at `now`: a window whose reset time has passed since the
/// last fetch has started over, so it reads 0 until the app fetches again.
private func percent(_ limit: PlanLimit?, at now: Date) -> Int {
    guard let limit else { return 0 }
    if let resetsAt = limit.resetsAt, resetsAt <= now { return 0 }
    return Int(limit.percent.rounded())
}

private func updatedText(_ usage: CachedUsage, now: Date) -> String {
    if now.timeIntervalSince(usage.updatedAt) < 60 { return "Updated just now" }
    return "Updated " + RelativeDateTimeFormatter().localizedString(for: usage.updatedAt, relativeTo: now)
}

private struct SmallUsageView: View {
    let usage: CachedUsage
    let now: Date

    var body: some View {
        let session = percent(usage.sessionLimit, at: now)
        let weekly = percent(usage.limits.first { $0.kind == "weekly_all" }, at: now)

        VStack(alignment: .leading) {
            HStack {
                Text("Session")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                UsageRing(fraction: Double(session) / 100)
                    .frame(width: 14, height: 14)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("\(session)%")
                    .font(.system(size: 40, weight: .semibold))
                    .tracking(-1)
                    .monospacedDigit()
                UsageBar(fraction: Double(session) / 100)
            }
            Spacer()
            HStack {
                Text(usage.sessionLimit?.resetText(now: now, compact: true) ?? "")
                Spacer()
                Text("Wk \(weekly)%")
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

private struct MediumUsageView: View {
    let usage: CachedUsage
    let now: Date

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                Text("Claude usage")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(usage.updatedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Grid(horizontalSpacing: 12, verticalSpacing: 14) {
                ForEach(usage.limits) { limit in
                    let value = percent(limit, at: now)
                    GridRow {
                        Text(limit.shortTitle)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .frame(width: 104, alignment: .leading)
                        UsageBar(fraction: Double(value) / 100)
                        Text("\(value)%")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            Spacer()
            Text("Session " + (usage.sessionLimit?.resetText(now: now).lowercasedFirstLetter ?? ""))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct LargeUsageView: View {
    let usage: CachedUsage
    let now: Date

    var body: some View {
        let session = percent(usage.sessionLimit, at: now)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude usage")
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 20) {
                ZStack {
                    UsageRing(fraction: Double(session) / 100, lineWidth: 8, trackOpacity: 0.08)
                    Text("\(session)%")
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current session")
                        .font(.system(size: 14, weight: .medium))
                    Text(usage.sessionLimit?.resetText(now: now) ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Divider()
            Spacer()
            VStack(spacing: 14) {
                ForEach(usage.weeklyLimits) { limit in
                    let value = percent(limit, at: now)
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(limit.title)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(value)%")
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                        }
                        UsageBar(fraction: Double(value) / 100)
                    }
                }
            }
            Spacer()
            Text(footer)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var subtitle: String? {
        let parts = [usage.email, usage.planName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var footer: String {
        let weekly = usage.limits.first { $0.kind == "weekly_all" }?.resetText(now: now)
        return [weekly.map { "Weekly " + $0.lowercasedFirstLetter }, updatedText(usage, now: now)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct NotConnectedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Not connected")
                .font(.system(size: 13, weight: .semibold))
            Text("Open Claude Usage on this Mac to show your limits.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private extension String {
    /// "Resets in 2 h" → "resets in 2 h", for joining after a leading word.
    var lowercasedFirstLetter: String {
        prefix(1).lowercased() + dropFirst()
    }
}

extension CachedUsage {
    static let sample = CachedUsage(
        limits: [
            PlanLimit(kind: "session", group: "session", percent: 42, severity: "normal",
                      resetsAt: .now.addingTimeInterval(2 * 3600 + 14 * 60), scope: nil, isActive: false),
            PlanLimit(kind: "weekly_all", group: "weekly", percent: 61, severity: "normal",
                      resetsAt: .now.addingTimeInterval(3 * 86400), scope: nil, isActive: false),
            PlanLimit(kind: "weekly_scoped", group: "weekly", percent: 18, severity: "normal",
                      resetsAt: .now.addingTimeInterval(3 * 86400),
                      scope: .init(model: .init(id: nil, displayName: "Fable")), isActive: false),
        ],
        email: "you@example.com",
        planName: "Max 5x",
        updatedAt: .now.addingTimeInterval(-60)
    )
}

#Preview("Small", as: .systemSmall) {
    UsageWidget()
} timeline: {
    UsageEntry(date: .now, usage: .sample)
}

#Preview("Medium", as: .systemMedium) {
    UsageWidget()
} timeline: {
    UsageEntry(date: .now, usage: .sample)
}

#Preview("Large", as: .systemLarge) {
    UsageWidget()
} timeline: {
    UsageEntry(date: .now, usage: .sample)
}
