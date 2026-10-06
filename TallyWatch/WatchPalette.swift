import SwiftUI

// Watch palette. The watch is always dark, so the dark variants of Tally's colors are used.

extension Color {
    init(watchHex hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        guard text.count == 6, Scanner(string: text).scanHexInt64(&value) else {
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum WatchPalette {
    static let paper = Color(watchHex: "#141413")
    static let surface = Color(watchHex: "#1E1E1C")
    static let sunken = Color(watchHex: "#2A2A27")
    static let ink = Color(watchHex: "#EDEAE2")
    static let inkSecondary = Color(watchHex: "#A19D93")
    static let rule = Color(watchHex: "#34332F")
    static let accent = Color(watchHex: "#5FB394")
    static let negative = Color(watchHex: "#E07A55")
    static let caution = Color(watchHex: "#DDB05A")

    /// Green until 85 %, ochre until 100 %, terracotta beyond.
    static func progressColor(_ progress: Double) -> Color {
        if progress > 1 { return negative }
        if progress >= 0.85 { return caution }
        return accent
    }
}

enum WatchFonts {
    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// Circular progress ring.
struct WatchRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8

    private var clamped: Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(WatchPalette.sunken, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    WatchPalette.progressColor(progress),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Thin horizontal progress bar.
struct WatchBar: View {
    var progress: Double
    var height: CGFloat = 4

    private var clamped: Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WatchPalette.sunken)
                Capsule()
                    .fill(WatchPalette.progressColor(progress))
                    .frame(width: max(proxy.size.width * clamped, clamped > 0 ? height : 0))
            }
        }
        .frame(height: height)
    }
}
