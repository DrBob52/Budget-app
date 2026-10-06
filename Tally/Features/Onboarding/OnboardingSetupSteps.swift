import SwiftUI
import TallyCore

// Steps 5 to 7: categories, first account and the closing summary.

// MARK: - Categories

struct OnboardingCategoriesStep: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var draft: OnboardingDraft

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top)
    ]

    var body: some View {
        OnboardingScaffold(
            title: "Pick your categories",
            subtitle: "Choose what you want to keep an eye on. Limits are suggestions based on your income, so adjust any of them."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                OnboardingAssignedSummary(assigned: draft.assignedTotal, income: draft.income)

                SectionHeader("Spending")
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(StarterCategories.expense) { template in
                        OnboardingCategoryCard(
                            template: template,
                            isSelected: draft.selectedExpenses.contains(template.name),
                            limit: draft.limitBinding(for: template),
                            onToggle: { toggleExpense(template) }
                        )
                    }
                }

                SectionHeader("Money in")
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(StarterCategories.income) { template in
                        OnboardingCategoryCard(
                            template: template,
                            isSelected: draft.selectedIncome.contains(template.name),
                            limit: nil,
                            onToggle: { toggleIncome(template) }
                        )
                    }
                }
            }
        }
    }

    private func toggleExpense(_ template: StarterCategories.Template) {
        if draft.selectedExpenses.contains(template.name) {
            draft.selectedExpenses.remove(template.name)
        } else {
            draft.selectedExpenses.insert(template.name)
        }
    }

    private func toggleIncome(_ template: StarterCategories.Template) {
        if draft.selectedIncome.contains(template.name) {
            draft.selectedIncome.remove(template.name)
        } else {
            draft.selectedIncome.insert(template.name)
        }
    }
}

/// "Assigned X of Y" with a thin bar.
struct OnboardingAssignedSummary: View {
    @Environment(AppSettings.self) private var settings
    let assigned: Decimal
    let income: Decimal

    private var progress: Double {
        guard income > 0 else { return 0 }
        return assigned.doubleValue / income.doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline("Assigned")
            if income > 0 {
                Text("\(settings.format(assigned, compact: true)) of \(settings.format(income, compact: true))")
                    .font(.display(24))
                    .foregroundStyle(Palette.ink)
                BudgetBar(progress: progress)
                Text(remainderText)
                    .font(.footnote)
                    .foregroundStyle(assigned > income ? Palette.negative : Palette.inkSecondary)
            } else {
                Text(settings.format(assigned, compact: true))
                    .font(.display(24))
                    .foregroundStyle(Palette.ink)
                Text("Add your income in the earlier step to see how much is left to assign.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .tallyCard()
    }

    private var remainderText: String {
        let difference: Decimal = income - assigned
        if difference >= 0 {
            return "\(settings.format(difference, compact: true)) left to assign"
        }
        return "\(settings.format(-difference, compact: true)) over your income"
    }
}

/// One category tile. Expense tiles show an editable limit once selected.
struct OnboardingCategoryCard: View {
    let template: StarterCategories.Template
    let isSelected: Bool
    /// Nil for categories that have no limit (income).
    let limit: Binding<Decimal>?
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    CategoryIcon(symbol: template.symbol, colorHex: template.colorHex, size: 30)
                    Text(template.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Palette.accent : Palette.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected, let limit {
                HStack(spacing: 6) {
                    AmountField(title: "No limit", amount: limit)
                    Text("limit")
                        .font(.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Palette.accent.opacity(0.7) : Palette.rule, lineWidth: isSelected ? 1.5 : Metrics.hairline)
        )
    }
}

// MARK: - First account

struct OnboardingAccountStep: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var draft: OnboardingDraft

    private let kindColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var balanceLabel: String {
        draft.accountKind.isLiability ? "Amount you owe today" : "Current balance"
    }

    var body: some View {
        OnboardingScaffold(
            title: "Add your first account",
            subtitle: "Where does your money live? One account is enough to begin, and you can add more later."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Overline("Name")
                    OnboardingFieldBox {
                        TextField("Everyday", text: $draft.accountName)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .textInputAutocapitalization(.words)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Overline("Type")
                    LazyVGrid(columns: kindColumns, spacing: 10) {
                        ForEach(AccountKind.allCases) { kind in
                            kindTile(kind)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Overline(balanceLabel)
                    OnboardingFieldBox {
                        AmountField(title: "0", amount: $draft.accountBalance)
                    }
                    Text("Optional. This is the starting point Tally counts from.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
    }

    private func kindTile(_ kind: AccountKind) -> some View {
        let isSelected: Bool = draft.accountKind == kind
        return Button {
            draft.accountKind = kind
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.defaultSymbol)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.inkSecondary)
                Text(kind.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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

// MARK: - Done

struct OnboardingDoneStep: View {
    @Environment(AppSettings.self) private var settings
    let draft: OnboardingDraft

    private var cycleText: String {
        switch settings.periodKind {
        case .monthly:
            return "Monthly, from the \(onboardingOrdinal(settings.monthlyStartDay))"
        case .weekly:
            return "Weekly, from \(onboardingWeekdayName(settings.weeklyStartWeekday))"
        case .biweekly:
            let date: String = settings.biweeklyAnchor.formatted(date: .abbreviated, time: .omitted)
            return "Every two weeks, next payday \(date)"
        }
    }

    private var incomeText: String {
        draft.income > 0 ? settings.format(draft.income, compact: true) : "Not set"
    }

    private var categoriesText: String {
        let count: Int = draft.chosenExpenses.count + draft.chosenIncome.count
        if count == 0 { return "None yet" }
        return count == 1 ? "1 category" : "\(count) categories"
    }

    private var accountText: String {
        draft.willCreateAccount ? draft.trimmedAccountName : "None yet"
    }

    var body: some View {
        OnboardingScaffold(
            title: "Your budget is ready",
            subtitle: "Here is what Tally will set up. Everything can be changed later."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingSummaryRow(label: "Currency", value: "\(CurrencyCatalog.name(for: settings.currencyCode)) (\(settings.currencyCode))")
                    Rule()
                    OnboardingSummaryRow(label: "Budget rhythm", value: cycleText)
                    Rule()
                    OnboardingSummaryRow(label: "Income", value: incomeText)
                    Rule()
                    OnboardingSummaryRow(label: "Categories", value: categoriesText)
                    if draft.income > 0 {
                        Rule()
                        OnboardingSummaryRow(
                            label: "Assigned",
                            value: "\(settings.format(draft.assignedTotal, compact: true)) of \(settings.format(draft.income, compact: true))"
                        )
                    }
                    Rule()
                    OnboardingSummaryRow(label: "Account", value: accountText)
                }
                .tallyCard()

                HStack(spacing: 14) {
                    OnboardingTallyMark(scale: 0.45)
                    Text("Add your first expense with the plus button and watch the bars fill in.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
    }
}
