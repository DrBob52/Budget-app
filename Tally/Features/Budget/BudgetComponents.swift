import SwiftUI
import SwiftData
import TallyCore

// Small building blocks used by the Plan tab. Everything here is prefixed `Budget`.

/// Money rendered in a chosen font and color, respecting privacy mode.
struct BudgetAmountLabel: View {
    @Environment(AppSettings.self) private var settings
    let amount: Decimal
    var font: Font = .amountSmall
    var color: Color = Palette.ink

    var body: some View {
        Text(settings.format(amount))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .hidesAmount(settings.hideAmounts)
    }
}

/// An entry in the "Not budgeted" section. `category == nil` means uncategorized spending.
struct BudgetUnbudgetedEntry: Identifiable {
    let category: Category?
    let spent: Decimal

    var id: String { category?.id.uuidString ?? "uncategorized" }
}

// MARK: - Hero

/// "Left to spend" summary with ring, daily allowance and income / spent / net.
struct BudgetHeroCard: View {
    @Environment(AppSettings.self) private var settings
    let summary: PeriodSummary

    private var progress: Double {
        guard summary.totalBudget > 0 else { return 0 }
        return (summary.expenses / summary.totalBudget).doubleValue
    }

    private var isOver: Bool { summary.leftToSpend < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Overline(isOver ? "Over budget" : "Left to spend")
                    MoneyText(
                        amount: isOver ? summary.leftToSpend.magnitudeValue : summary.leftToSpend,
                        font: .display(38),
                        colored: isOver
                    )
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    allowanceLine
                }
                Spacer(minLength: 0)
                ring
            }
            Rule()
            BudgetStatsRow(summary: summary)
        }
        .tallyCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var ring: some View {
        ZStack {
            ProgressRing(progress: progress, lineWidth: 8)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.system(.footnote, design: .serif).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isOver ? Palette.negative : Palette.ink)
                .hidesAmount(settings.hideAmounts)
        }
        .frame(width: 76, height: 76)
    }

    @ViewBuilder
    private var allowanceLine: some View {
        if let allowance = summary.dailyAllowance, summary.leftToSpend > 0 {
            let days = summary.daysRemaining
            Text("≈ \(settings.format(allowance)) per day for ^[\(days) day](inflect: true)")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .hidesAmount(settings.hideAmounts)
        } else if isOver {
            Text("Spending has passed the plan by \(settings.format(summary.leftToSpend.magnitudeValue))")
                .font(.footnote)
                .foregroundStyle(Palette.negative)
                .hidesAmount(settings.hideAmounts)
        } else {
            Text("of \(settings.format(summary.totalBudget)) planned")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .hidesAmount(settings.hideAmounts)
        }
    }

    private var accessibilitySummary: String {
        if settings.hideAmounts { return String(localized: "Budget summary, amounts hidden") }
        let left = settings.format(summary.leftToSpend.magnitudeValue)
        let lead = isOver ? String(localized: "Over budget by \(left)") : String(localized: "\(left) left to spend")
        return String(localized: "\(lead). Income \(settings.format(summary.income)), spent \(settings.format(summary.expenses)), net \(settings.format(summary.net)).")
    }
}

/// Income / Spent / Net mini stats.
struct BudgetStatsRow: View {
    let summary: PeriodSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            stat("Income") {
                MoneyText(amount: summary.income, font: .amountSmall)
            }
            stat("Spent") {
                MoneyText(amount: summary.expenses, font: .amountSmall)
            }
            stat("Net") {
                MoneyText(amount: summary.net, showsSign: true, font: .amountSmall, colored: true)
            }
        }
    }

    private func stat<Content: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Overline(title)
            value()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown instead of the hero when no category has a limit yet.
struct BudgetSetupPromptCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline("Start planning")
            Text("Give your money a plan")
                .font(.titleSerif)
                .foregroundStyle(Palette.ink)
            Text("Set a limit for the categories you care about and Tally will show what is left to spend, day by day.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set category limits", action: action)
                .buttonStyle(.tallyPrimary)
                .padding(.top, 4)
        }
        .tallyCard()
    }
}

// MARK: - Rows

/// A budgeted category: icon, name, bar and what is left.
struct BudgetCategoryRow: View {
    @Environment(AppSettings.self) private var settings
    let category: Category
    let status: CategoryStatus

    private var isOver: Bool { status.remaining < 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(category: category, size: 36)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(category.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    remainingLabel
                }
                BudgetBar(progress: status.progress)
                    .accessibilityHidden(true)
                if status.carriedOver != 0 {
                    Text(carryNote)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .hidesAmount(settings.hideAmounts)
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.inkTertiary)
                .padding(.top, 10)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows this category's transactions")
    }

    private var remainingLabel: some View {
        HStack(spacing: 4) {
            BudgetAmountLabel(
                amount: status.remaining.magnitudeValue,
                font: .amountSmall,
                color: isOver ? Palette.negative : Palette.ink
            )
            Text(isOver ? "over" : "left")
                .font(.caption)
                .foregroundStyle(isOver ? Palette.negative : Palette.inkSecondary)
        }
    }

    private var carryNote: String {
        let amount = settings.format(status.carriedOver.magnitudeValue)
        if status.carriedOver > 0 {
            return String(localized: "Includes \(amount) carried over")
        }
        return String(localized: "Reduced by \(amount) overspent earlier")
    }

    private var accessibilityText: String {
        if settings.hideAmounts { return String(localized: "\(category.name), amounts hidden") }
        let amount = settings.format(status.remaining.magnitudeValue)
        let available = settings.format(status.available)
        let text: String = isOver
            ? String(localized: "\(category.name), \(amount) over of \(available)")
            : String(localized: "\(category.name), \(amount) left of \(available)")
        if status.carriedOver != 0 {
            return String(localized: "\(text), \(carryNote.lowercased())")
        }
        return text
    }
}

/// A category (or uncategorized spending) without a limit this period.
struct BudgetUnbudgetedRow: View {
    @Environment(AppSettings.self) private var settings
    let entry: BudgetUnbudgetedEntry
    let onSetLimit: (Category) -> Void

    private var name: String { entry.category?.name ?? String(localized: "Uncategorized") }

    var body: some View {
        HStack(spacing: 12) {
            if let category = entry.category {
                CategoryIcon(category: category, size: 36)
            } else {
                CategoryIcon(symbol: "questionmark", colorHex: "#9C978C", size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    BudgetAmountLabel(amount: entry.spent, font: .amountSmall, color: Palette.inkSecondary)
                    Text("spent")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: 8)
            if let category = entry.category {
                Button("Set limit") { onSetLimit(category) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: "Set limit") {
            if let category = entry.category { onSetLimit(category) }
        }
    }

    private var accessibilityText: String {
        if settings.hideAmounts { return String(localized: "\(name), no limit, amounts hidden") }
        return String(localized: "\(name), \(settings.format(entry.spent)) spent, no limit set")
    }
}

// MARK: - Set limit sheet

/// Quick sheet that sets a single category's limit.
struct BudgetSetLimitSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    let category: Category
    let spent: Decimal

    @State private var amount: Decimal

    init(category: Category, spent: Decimal = 0) {
        self.category = category
        self.spent = spent
        _amount = State(initialValue: category.budgetLimit)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    CategoryIcon(category: category, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.headlineSerif)
                            .foregroundStyle(Palette.ink)
                        if spent > 0 {
                            Text("\(settings.format(spent)) spent this period")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                                .hidesAmount(settings.hideAmounts)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Overline("Limit per period")
                    AmountField(title: "0", amount: $amount, large: true)
                    Rule()
                }
                Text("Anything above this counts as over budget for the period.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: 0)
            }
            .padding(Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tallyScreen()
            .navigationTitle("Set limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        category.budgetLimit = amount
                        try? context.save()
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
