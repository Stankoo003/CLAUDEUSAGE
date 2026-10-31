import AppKit
import SwiftUI

/// The usage card from the design ("Menu bar — light/dark"), shown in the main window
/// and in the menu bar popover.
struct ContentView: View {
    enum Layout {
        /// Resizable; the limits scroll when the window is shorter than they are.
        case window
        /// Fixed 320 pt card that fits its content, as in the design.
        case menuBar
    }

    let layout: Layout

    @Environment(UsageStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        switch layout {
        case .window:
            panel
                .frame(minWidth: 300, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
        case .menuBar:
            panel
                .frame(width: 320)
        }
    }

    private var panel: some View {
        // Re-render every 30 s so "Resets in…" and "Updated…" stay current between fetches.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                header
                Divider()
                if layout == .window {
                    ScrollView {
                        content(now: context.date)
                            .padding(16)
                    }
                } else {
                    content(now: context.date)
                        .padding(16)
                }
                Divider()
                footer(now: context.date)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude usage")
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Group {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                }
            }
            .frame(width: 28, height: 28)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 12))
    }

    private var subtitle: String? {
        let parts = [store.email, store.planName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if !store.limits.isEmpty {
            VStack(spacing: 18) {
                ForEach(store.limits) { limit in
                    LimitRow(limit: limit, now: now)
                }
            }
        } else {
            switch store.status {
            case .loading, .ready:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading usage…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            case .signedOut(let message):
                MessageView(
                    title: "Not connected",
                    message: message + "\nSign in with `claude` in Terminal, then try again.",
                    retry: store.retry
                )
            case .failed(let message):
                MessageView(title: "Couldn't load usage", message: message, retry: store.retry)
            }
        }
    }

    private func footer(now: Date) -> some View {
        HStack {
            Text(footerText(now: now))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if layout == .menuBar {
                Button {
                    openWindow(id: "main")
                    NSApplication.shared.activate()
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .help("Open window")
            }
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .help("Quit")
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 12))
    }

    private func footerText(now: Date) -> String {
        // With data on screen, a failed refresh only shows here so the last-known bars stay visible.
        if !store.limits.isEmpty {
            switch store.status {
            case .signedOut(let message), .failed(let message):
                return message
            case .loading, .ready:
                break
            }
        }
        guard let lastUpdated = store.lastUpdated else { return "Not updated yet" }
        if now.timeIntervalSince(lastUpdated) < 60 { return "Updated just now" }
        return "Updated " + lastUpdated.formatted(.relative(presentation: .named))
    }
}

private struct LimitRow: View {
    let limit: PlanLimit
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(limit.percent.rounded()))%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            UsageBar(fraction: limit.fraction)
            Text(resetText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(limit.title)
        .accessibilityValue("\(Int(limit.percent.rounded())) percent. \(resetText)")
    }

    private var resetText: String {
        limit.resetText(now: now)
    }
}

private struct MessageView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(.init(message))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Window") {
    ContentView(layout: .window)
        .environment(UsageStore.preview)
}

#Preview("Menu bar") {
    ContentView(layout: .menuBar)
        .environment(UsageStore.preview)
}
