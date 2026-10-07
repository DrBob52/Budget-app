import SwiftUI
import Charts
import TallyCore

// Shared building blocks for the Insights cards.

extension View {
    /// Left-hand money axis with thin rules and compact amounts.
    func insightsMoneyAxis(_ settings: AppSettings) -> some View {
        self.chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Palette.rule)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(settings.format(Decimal(amount), compact: true))
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
        }
    }

    /// Bottom axis for charts whose x values are short text labels.
    func insightsLabelAxis() -> some View {
        self.chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let text = value.as(String.self) {
                        Text(text)
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
        }
    }

    /// Blurs chart content while privacy mode is on.
    func insightsPrivacy(_ hidden: Bool) -> some View {
        self
            .blur(radius: hidden ? 8 : 0)
            .accessibilityHidden(hidden)
    }
}

/// Section header above a hairline card.
struct InsightsSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .tallyCard()
        }
    }
}

/// Blurs a Pro-only card and offers the paywall.
struct InsightsProGate: ViewModifier {
    @Environment(AppRouter.self) private var router
    let locked: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: locked ? 7 : 0)
            .allowsHitTesting(!locked)
            .accessibilityHidden(locked)
            .overlay {
                if locked {
                    Button {
                        router.sheet = .paywall
                    } label: {
                        Label("Unlock with Tally Pro", systemImage: "lock.fill")
                    }
                    .buttonStyle(.tallyPrimary)
                    .frame(maxWidth: 260)
                }
            }
    }
}

extension View {
    func insightsProGate(locked: Bool) -> some View {
        modifier(InsightsProGate(locked: locked))
    }
}

/// Small caption used under charts and in empty cards.
struct InsightsNote: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Palette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Overline + amount pair used in the summary strip.
struct InsightsStat: View {
    let title: LocalizedStringKey
    let amount: Decimal
    var showsSign = false
    var colored = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Overline(title)
            MoneyText(amount: amount, showsSign: showsSign, compact: true, font: .display(22), colored: colored)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
