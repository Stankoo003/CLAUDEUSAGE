import AppKit
import SwiftUI

/// The menu bar item from the design: a ring and the current session's percentage.
///
/// `MenuBarExtra` labels only render text and images, so the ring is drawn into a
/// template image, which macOS tints for light and dark menu bars.
struct MenuBarLabel: View {
    let store: UsageStore

    var body: some View {
        Image(nsImage: MenuBarIcon(state: state).render())
            .accessibilityLabel(accessibilityText)
    }

    private var state: MenuBarIcon.State {
        guard let session = store.sessionLimit else { return .unavailable }
        return session.isReached ? .reached : .percent(session.percent)
    }

    private var accessibilityText: String {
        switch state {
        case .percent(let percent): "Claude usage, \(Int(percent.rounded())) percent"
        case .reached: "Claude usage, limit reached"
        case .unavailable: "Claude usage, not connected"
        }
    }
}

private struct MenuBarIcon: View {
    enum State {
        case percent(Double)
        case reached
        case unavailable
    }

    let state: State

    var body: some View {
        switch state {
        case .percent(let percent):
            content(ring: UsageRing(fraction: percent / 100), text: "\(Int(percent.rounded()))%")
        case .reached:
            // Inverted pill: the ring and text are cut out of a filled background.
            content(ring: UsageRing(fraction: 1, showsTrack: false), text: "100%")
                .blendMode(.destinationOut)
                .background(RoundedRectangle(cornerRadius: 5).fill(.black))
                .compositingGroup()
        case .unavailable:
            content(ring: DashedRing(), text: "—")
                .opacity(0.55)
        }
    }

    private func content(ring: some View, text: String) -> some View {
        HStack(spacing: 5) {
            ring
                .frame(width: 14, height: 14)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 6)
        .frame(height: 18)
    }

    func render() -> NSImage {
        let renderer = ImageRenderer(content: self)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}

private struct DashedRing: View {
    var body: some View {
        Circle()
            .inset(by: 1.5)
            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [2, 2.32]))
    }
}
