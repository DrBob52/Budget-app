import SwiftUI
import TallyCore

// MARK: - Containers

struct CardModifier: ViewModifier {
    var padding: CGFloat = Metrics.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .strokeBorder(Palette.rule, lineWidth: Metrics.hairline)
            )
    }
}

extension View {
    /// Paper card with a hairline outline.
    func tallyCard(padding: CGFloat = Metrics.cardPadding) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Paper background for a whole screen, including behind lists and forms.
    func tallyScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
    }

    /// Hides money when privacy mode is on.
    func hidesAmount(_ hidden: Bool) -> some View {
        self.redacted(reason: hidden ? .privacy : [])
    }
}

// Components that show a title take a `LocalizedStringKey` so string literals are translated,
// plus a disfavored `StringProtocol` overload for text that is already final (names, amounts).

/// Uppercase, letter-spaced section label.
struct Overline: View {
    let text: Text

    init(_ key: LocalizedStringKey) { self.text = Text(key) }

    @_disfavoredOverload
    init<S: StringProtocol>(_ verbatim: S) { self.text = Text(verbatim) }

    var body: some View {
        text
            .textCase(.uppercase)
            .font(.overline)
            .tracking(1.4)
            .foregroundStyle(Palette.inkSecondary)
    }
}

/// Section header with an optional trailing action, used above cards.
struct SectionHeader<Trailing: View>: View {
    let title: Overline
    @ViewBuilder var trailing: () -> Trailing

    init(_ key: LocalizedStringKey, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = Overline(key)
        self.trailing = trailing
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ verbatim: S, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = Overline(verbatim)
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
            Spacer()
            trailing()
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ key: LocalizedStringKey) {
        self.init(key) { EmptyView() }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ verbatim: S) {
        self.init(verbatim) { EmptyView() }
    }
}

/// A full-width hairline rule.
struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(Palette.rule)
            .frame(height: Metrics.hairline)
    }
}

// MARK: - Money

/// Formats an amount in the user's currency, respecting privacy mode.
struct MoneyText: View {
    @Environment(AppSettings.self) private var settings
    let amount: Decimal
    var showsSign = false
    var compact = false
    var font: Font = .amount
    /// Colors positive values green and negative terracotta.
    var colored = false

    var body: some View {
        Text(settings.format(amount, showsSign: showsSign, compact: compact))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .hidesAmount(settings.hideAmounts)
            .contentTransition(.numericText())
    }

    private var color: Color {
        guard colored else { return Palette.ink }
        if amount > 0 { return Palette.positive }
        if amount < 0 { return Palette.negative }
        return Palette.ink
    }
}

/// Text field for entering money. Accepts the locale's decimal separator.
struct AmountField: View {
    @Environment(AppSettings.self) private var settings
    let title: LocalizedStringKey
    @Binding var amount: Decimal
    var large = false

    @State private var text = ""
    @FocusState private var focused: Bool

    init(title: LocalizedStringKey, amount: Binding<Decimal>, large: Bool = false) {
        self.title = title
        self._amount = amount
        self.large = large
    }

    @_disfavoredOverload
    init<S: StringProtocol>(title: S, amount: Binding<Decimal>, large: Bool = false) {
        self.init(title: LocalizedStringKey(String(title)), amount: amount, large: large)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(MoneyFormat.symbol(for: settings.currencyCode))
                .font(large ? .display(28, weight: .regular) : .amount)
                .foregroundStyle(Palette.inkSecondary)
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .font(large ? .display(44) : .amount)
                .foregroundStyle(Palette.ink)
                .focused($focused)
                .onChange(of: text) { _, newValue in
                    amount = AmountField.parse(newValue) ?? 0
                }
        }
        .onAppear {
            text = amount == 0 ? "" : AmountField.editingString(amount)
        }
        .onChange(of: amount) { _, newValue in
            if !focused, AmountField.parse(text) != newValue {
                text = newValue == 0 ? "" : AmountField.editingString(newValue)
            }
        }
    }

    static func parse(_ text: String) -> Decimal? {
        StatementImporter.parseAmount(text, decimalSeparator: Locale.current.decimalSeparator?.first)
            .map { $0.magnitudeValue }
    }

    static func editingString(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - Progress

/// Thin horizontal bar. Over-limit values fill completely in terracotta.
struct BudgetBar: View {
    let progress: Double
    var height: CGFloat = 6
    var tint: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.sunken)
                Capsule()
                    .fill(tint ?? Palette.progressColor(progress))
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: progress)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
    }
}

/// Circular ring used for goals and the budget hero.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color? = nil

    var body: some View {
        ZStack {
            Circle().stroke(Palette.sunken, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint ?? Palette.progressColor(progress), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}

// MARK: - Icons

/// SF Symbol on a tinted rounded square.
struct CategoryIcon: View {
    let symbol: String
    let colorHex: String
    var size: CGFloat = 32

    var body: some View {
        let color = Color(hex: colorHex)
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension CategoryIcon {
    init(category: Category?, size: CGFloat = 32) {
        self.init(symbol: category?.symbol ?? "questionmark", colorHex: category?.colorHex ?? "#9C978C", size: size)
    }
}

/// Member initials in a colored circle.
struct MemberAvatar: View {
    let member: Member
    var size: CGFloat = 30

    var body: some View {
        Text(member.initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .serif))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: member.colorHex), in: Circle())
            .accessibilityLabel(member.name)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Palette.paper)
            .background(Palette.ink.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.3),
                        in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(Palette.ink)
            .background(configuration.isPressed ? Palette.sunken : Palette.surface,
                        in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous).strokeBorder(Palette.rule))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var tallyPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var tallySecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Round ink button that opens the quick-add sheet.
struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.paper)
                .frame(width: 56, height: 56)
                .background(Palette.ink, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .accessibilityLabel("Add transaction")
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.inkTertiary)
            Text(title)
                .font(.headlineSerif)
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.tallySecondary)
                    .frame(maxWidth: 220)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Period navigation

/// "‹ October 2026 ›" control. Shared by Budget, Ledger and Insights.
struct PeriodNavigator: View {
    @Environment(AppSettings.self) private var settings
    @Binding var period: BudgetPeriod

    var body: some View {
        let calculator = settings.periodCalculator
        let isCurrent = period.isCurrent()
        HStack(spacing: 4) {
            Button {
                period = calculator.period(before: period)
            } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            .accessibilityLabel("Previous period")

            Button {
                period = calculator.period(containing: Date())
            } label: {
                VStack(spacing: 1) {
                    Text(period.title())
                        .font(.headlineSerif)
                        .foregroundStyle(Palette.ink)
                    if !isCurrent {
                        Text("Back to today")
                            .font(.caption2)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .frame(minWidth: 160)
            }
            .disabled(isCurrent)

            Button {
                period = calculator.period(after: period)
            } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .accessibilityLabel("Next period")
        }
        .foregroundStyle(Palette.ink)
        .buttonStyle(.plain)
    }
}
