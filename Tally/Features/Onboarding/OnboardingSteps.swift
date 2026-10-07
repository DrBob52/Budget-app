import SwiftUI
import TallyCore

// Steps 1 to 4: welcome, currency, budget rhythm and income.

// MARK: - Welcome

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            OnboardingTallyMark(scale: 1.3)
            VStack(spacing: 12) {
                Text("Tally")
                    .font(.display(60))
                    .foregroundStyle(Palette.ink)
                Text("Know where your money goes, and decide where it goes next.")
                    .font(.title3)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, Metrics.screenPadding + 4)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Currency

struct OnboardingCurrencyStep: View {
    @Environment(AppSettings.self) private var settings
    @State private var query: String = ""
    @State private var currencies: [CurrencyInfo] = []

    private var filtered: [CurrencyInfo] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return currencies }
        return currencies.filter { info in
            info.name.localizedCaseInsensitiveContains(text) || info.code.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        OnboardingScaffold(
            title: "Which currency do you use?",
            subtitle: "Every amount in Tally is shown in this currency. You can change it later in Settings."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                selectedRow
                searchField
                list
            }
        }
        .task {
            if currencies.isEmpty {
                currencies = CurrencyCatalog.all
            }
        }
    }

    private var selectedRow: some View {
        HStack(spacing: 12) {
            Text(MoneyFormat.symbol(for: settings.currencyCode))
                .font(.display(24))
                .foregroundStyle(Palette.accent)
                .frame(minWidth: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(CurrencyCatalog.name(for: settings.currencyCode))
                    .font(.headlineSerif)
                    .foregroundStyle(Palette.ink)
                Text(settings.currencyCode)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
        }
        .tallyCard()
    }

    private var searchField: some View {
        OnboardingFieldBox {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.inkTertiary)
                TextField("Search currencies", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Palette.ink)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
        }
    }

    private var list: some View {
        let rows: [CurrencyInfo] = filtered
        return VStack(spacing: 0) {
            if rows.isEmpty {
                Text("No currency matches that search.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(Metrics.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { info in
                        currencyRow(info)
                        if info.id != rows.last?.id {
                            Rule().padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(Palette.rule, lineWidth: Metrics.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    private func currencyRow(_ info: CurrencyInfo) -> some View {
        let isSelected: Bool = info.code == settings.currencyCode
        return Button {
            settings.currencyCode = info.code
        } label: {
            HStack(spacing: 12) {
                Text(info.code)
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: 46, alignment: .leading)
                Text(info.name)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Budget rhythm

struct OnboardingRhythmStep: View {
    @Environment(AppSettings.self) private var settings

    private let kinds: [PeriodKind] = [.monthly, .biweekly, .weekly]

    var body: some View {
        OnboardingScaffold(
            title: "How often do you plan?",
            subtitle: "Tally starts a fresh budget at the rhythm of your pay, so the numbers line up with real life."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(kinds) { kind in
                    kindCard(kind)
                }
                OnboardingRhythmDetail()
                    .padding(.top, 4)
            }
        }
    }

    private func blurb(for kind: PeriodKind) -> String {
        switch kind {
        case .monthly: return String(localized: "One budget a month, starting on your payday.")
        case .biweekly: return String(localized: "A new budget every two weeks, in step with your pay.")
        case .weekly: return String(localized: "A fresh budget every week.")
        }
    }

    private func symbol(for kind: PeriodKind) -> String {
        switch kind {
        case .monthly: return "calendar"
        case .biweekly: return "calendar.badge.clock"
        case .weekly: return "calendar.badge.plus"
        }
    }

    private func kindCard(_ kind: PeriodKind) -> some View {
        let isSelected: Bool = settings.periodKind == kind
        return Button {
            settings.periodKind = kind
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol(for: kind))
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.inkSecondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.displayName)
                        .font(.headlineSerif)
                        .foregroundStyle(Palette.ink)
                    Text(blurb(for: kind))
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.accent : Palette.inkTertiary)
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent : Palette.rule, lineWidth: isSelected ? 1.5 : Metrics.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The payday question that goes with the chosen rhythm.
struct OnboardingRhythmDetail: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var bound = settings
        VStack(alignment: .leading, spacing: 12) {
            switch settings.periodKind {
            case .monthly:
                HStack {
                    Text("Which day do you get paid?")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Picker("Payday", selection: $bound.monthlyStartDay) {
                        ForEach(1..<29, id: \.self) { day in
                            Text(onboardingOrdinal(day)).tag(day)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            case .weekly:
                HStack {
                    Text("Which day do you get paid?")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Picker("Payday", selection: $bound.weeklyStartWeekday) {
                        ForEach(1..<8, id: \.self) { weekday in
                            Text(onboardingWeekdayName(weekday)).tag(weekday)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            case .biweekly:
                DatePicker(
                    "Date of your next payday",
                    selection: $bound.biweeklyAnchor,
                    displayedComponents: .date
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink)
            }
            Rule()
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Palette.accent)
                Text("Current budget: \(settings.currentPeriod.title())")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .tallyCard()
    }
}

// MARK: - Income

struct OnboardingIncomeStep: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var draft: OnboardingDraft

    private var incomeQuestion: String {
        switch settings.periodKind {
        case .monthly: return String(localized: "What do you expect to earn each month?")
        case .biweekly: return String(localized: "What do you expect to earn every two weeks?")
        case .weekly: return String(localized: "What do you expect to earn each week?")
        }
    }

    private var incomeOverline: String {
        switch settings.periodKind {
        case .monthly: return String(localized: "Expected income per month")
        case .biweekly: return String(localized: "Expected income per two weeks")
        case .weekly: return String(localized: "Expected income per week")
        }
    }

    var body: some View {
        OnboardingScaffold(
            title: Text(incomeQuestion),
            subtitle: Text("A rough figure is fine. Tally uses it to suggest sensible limits in the next step.")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Overline(incomeOverline)
                    AmountField(title: "0", amount: $draft.income, large: true)
                }
                .tallyCard()
                Text("Not sure yet? Skip this and set limits by hand. You can change it any time.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}
