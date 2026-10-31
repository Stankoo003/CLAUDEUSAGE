import SwiftUI

/// Horizontal usage bar from the design: a faint track with a solid fill in the foreground color.
struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.08))
                Capsule()
                    .fill(.primary)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

/// Circular usage ring, drawn in the current foreground style.
struct UsageRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 2
    var trackOpacity: Double = 0.22
    var showsTrack = true

    var body: some View {
        ZStack {
            if showsTrack {
                Circle()
                    .inset(by: lineWidth / 2 + 0.5)
                    .stroke(lineWidth: lineWidth)
                    .opacity(trackOpacity)
            }
            Circle()
                .inset(by: lineWidth / 2 + 0.5)
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
