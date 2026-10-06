import SwiftUI
import UIKit

// Tally's look: warm paper, dark ink, serif numerals, hairline rules and a muted
// earth-tone palette. Icons are monochrome SF Symbols in small rounded squares.

extension Color {
    /// Creates a color from "#RRGGBB" or "RRGGBB". Falls back to gray.
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// Light and dark variants in one dynamic color.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: String) {
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

enum Palette {
    /// Screen background.
    static let paper = Color(light: "#F3EFE6", dark: "#141413")
    /// Card and sheet background.
    static let surface = Color(light: "#FBF9F4", dark: "#1E1E1C")
    /// Slightly darker fill for inputs and pressed states.
    static let sunken = Color(light: "#ECE7DC", dark: "#262624")
    static let ink = Color(light: "#1A1A18", dark: "#EDEAE2")
    static let inkSecondary = Color(light: "#6B675F", dark: "#A19D93")
    static let inkTertiary = Color(light: "#9C978C", dark: "#6E6A62")
    /// Hairline dividers and card outlines.
    static let rule = Color(light: "#DCD6CA", dark: "#34332F")
    /// Brand accent: deep forest green.
    static let accent = Color(light: "#1F5C4A", dark: "#5FB394")
    static let positive = accent
    /// Over budget, deletions and money out.
    static let negative = Color(light: "#B84A26", dark: "#E07A55")
    /// Close to the limit.
    static let caution = Color(light: "#B7862B", dark: "#DDB05A")

    /// Category / account / goal colors. Stored as hex on the models.
    static let swatches: [String] = [
        "#1F5C4A", "#2E6F5E", "#3E7C8C", "#2F4B7C", "#4A5560", "#6B4E71",
        "#A23B57", "#B84A26", "#C07A2C", "#B7862B", "#5A6B2F", "#8A5A44"
    ]

    /// Fill for a progress value: green until 85 %, ochre until 100 %, terracotta beyond.
    static func progressColor(_ progress: Double) -> Color {
        if progress > 1 { return negative }
        if progress >= 0.85 { return caution }
        return accent
    }
}

enum Metrics {
    static let cornerRadius: CGFloat = 10
    static let smallCornerRadius: CGFloat = 6
    static let hairline: CGFloat = 1
    static let screenPadding: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let rowSpacing: CGFloat = 12
}

extension Font {
    /// Big serif numbers for hero amounts.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Serif title for screen and card headers.
    static let titleSerif = Font.system(.title2, design: .serif).weight(.semibold)
    static let headlineSerif = Font.system(.headline, design: .serif)
    /// Tabular amounts in rows.
    static let amount = Font.system(.body, design: .serif).weight(.medium).monospacedDigit()
    static let amountSmall = Font.system(.subheadline, design: .serif).monospacedDigit()
    /// Uppercase overline labels.
    static let overline = Font.system(size: 11, weight: .semibold)
}

/// SF Symbols offered in the icon picker.
enum SymbolCatalog {
    static let all: [String] = [
        "house", "cart", "fork.knife", "cup.and.saucer", "tram", "car", "fuelpump", "bicycle",
        "airplane", "bolt", "drop", "flame", "wifi", "phone", "repeat", "bag", "tshirt",
        "gift", "cross.case", "pills", "heart", "dumbbell", "figure.walk", "pawprint",
        "graduationcap", "book", "theatermasks", "gamecontroller", "music.note", "film",
        "paintbrush", "wrench.and.screwdriver", "hammer", "leaf", "tree", "sun.max",
        "briefcase", "building.2", "building.columns", "banknote", "creditcard", "dollarsign.circle",
        "chart.line.uptrend.xyaxis", "sparkles", "star", "lifepreserver", "umbrella", "shield",
        "person.2", "figure.2.and.child.holdinghands", "stroller", "baby", "scissors", "sofa",
        "tv", "laptopcomputer", "iphone", "camera", "envelope", "doc.text", "tag", "ellipsis.circle",
        "arrow.uturn.backward", "archivebox", "wallet.pass", "globe", "mappin", "beach.umbrella"
    ]
}
