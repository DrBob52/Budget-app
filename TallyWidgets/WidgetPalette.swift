import SwiftUI
import UIKit

// Small self-contained palette for the widget extension (the app's DesignSystem is not
// compiled into this target). Mirrors Tally's paper / ink / forest / terracotta look.

extension UIColor {
    convenience init(widgetHex hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        guard text.count == 6, Scanner(string: text).scanHexInt64(&value) else {
            self.init(white: 0.5, alpha: 1)
            return
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(widgetHex hex: String) {
        self.init(uiColor: UIColor(widgetHex: hex))
    }

    init(widgetLight light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(widgetHex: dark) : UIColor(widgetHex: light)
        })
    }
}

enum WidgetPalette {
    static let paper = Color(widgetLight: "#F3EFE6", dark: "#141413")
    static let sunken = Color(widgetLight: "#E4DED1", dark: "#2A2A27")
    static let ink = Color(widgetLight: "#1A1A18", dark: "#EDEAE2")
    static let inkSecondary = Color(widgetLight: "#6B675F", dark: "#A19D93")
    static let rule = Color(widgetLight: "#DCD6CA", dark: "#34332F")
    static let accent = Color(widgetLight: "#1F5C4A", dark: "#5FB394")
    static let negative = Color(widgetLight: "#B84A26", dark: "#E07A55")
    static let caution = Color(widgetLight: "#B7862B", dark: "#DDB05A")

    /// Green until 85 %, ochre until 100 %, terracotta beyond.
    static func progressColor(_ progress: Double) -> Color {
        if progress > 1 { return negative }
        if progress >= 0.85 { return caution }
        return accent
    }
}

enum WidgetFonts {
    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func label(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold)
    }
}

/// Thin rounded progress bar.
struct WidgetBar: View {
    var progress: Double
    var color: Color? = nil
    var height: CGFloat = 4

    private var clamped: Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.sunken)
                Capsule()
                    .fill(color ?? WidgetPalette.progressColor(progress))
                    .frame(width: max(proxy.size.width * clamped, clamped > 0 ? height : 0))
            }
        }
        .frame(height: height)
    }
}

/// Hairline rule.
struct WidgetRule: View {
    var body: some View {
        Rectangle()
            .fill(WidgetPalette.rule)
            .frame(height: 1)
    }
}
