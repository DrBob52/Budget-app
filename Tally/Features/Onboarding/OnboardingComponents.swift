import SwiftUI

// Small building blocks shared by the onboarding steps.

/// Four ink strokes with a green diagonal, echoing the app icon.
struct OnboardingTallyMark: View {
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            HStack(spacing: 18 * scale) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule()
                        .fill(Palette.ink)
                        .frame(width: 8 * scale, height: 96 * scale)
                }
            }
            Capsule()
                .fill(Palette.accent)
                .frame(width: 140 * scale, height: 9 * scale)
                .rotationEffect(.degrees(-38))
        }
        .frame(width: 150 * scale, height: 112 * scale)
        .accessibilityHidden(true)
    }
}

/// Scrolling page with a serif title and a short explanation above the step's content.
struct OnboardingScaffold<Content: View>: View {
    let title: Text
    let subtitle: Text
    let content: Content

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.subtitle = Text(subtitle)
        self.content = content()
    }

    /// For copy that is already final, e.g. a localized `String` computed elsewhere.
    init(title: Text, subtitle: Text, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.display(30))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(.horizontal, Metrics.screenPadding + 4)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// "1st", "2nd", "3rd" in the user's language.
func onboardingOrdinal(_ number: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
}

/// Name of a weekday number, 1 = Sunday ... 7 = Saturday.
func onboardingWeekdayName(_ weekday: Int) -> String {
    let symbols: [String] = Calendar.current.weekdaySymbols
    let index: Int = weekday - 1
    guard index >= 0, index < symbols.count else { return "" }
    return symbols[index]
}

/// Label and value on one line, used in the final summary.
struct OnboardingSummaryRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Rounded white-on-paper field container used for text inputs.
struct OnboardingFieldBox<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .strokeBorder(Palette.rule, lineWidth: Metrics.hairline)
            )
    }
}
