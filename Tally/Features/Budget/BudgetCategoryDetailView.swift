import SwiftUI
import SwiftData
import TallyCore

/// One budgeted category: its limit, what is left, and the period's transactions.
struct BudgetCategoryDetailView: View {
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    let category: Category
    let period: BudgetPeriod

    @State private var showingEditor = false
    @State private var editingTransaction: Transaction?

    init(category: Category, period: BudgetPeriod) {
        self.category = category
        self.period = period
    }

    private var periodTransactions: [Transaction] {
        let id: UUID = category.id
        return transactions.filter { transaction in
            transaction.kind == .expense
                && transaction.category?.id == id
                && period.contains(transaction.date)
        }
    }

    private var status: CategoryStatus? {
        let summary: PeriodSummary = BudgetService.summary(
            for: period,
            transactions: transactions,
            categories: categories,
            settings: settings
        )
        return summary.status(for: category.id)
    }

    var body: some View {
        let rows: [Transaction] = periodTransactions
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard(rows: rows)
                transactionsSection(rows: rows)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .tallyScreen()
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            CategoryEditorView(category: category)
        }
        .sheet(item: $editingTransaction) { transaction in
            TransactionEditorView(transaction: transaction)
        }
    }

    // MARK: Header

    private func headerCard(rows: [Transaction]) -> some View {
        let spent: Decimal = rows.reduce(Decimal(0)) { $0 + $1.amount }
        let current: CategoryStatus? = status
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CategoryIcon(category: category, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.titleSerif)
                        .foregroundStyle(Palette.ink)
                    Text(period.title())
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            if let current {
                budgetedBody(status: current)
            } else {
                unbudgetedBody(spent: spent)
            }
        }
        .tallyCard()
    }

    private func budgetedBody(status: CategoryStatus) -> some View {
        let isOver: Bool = status.remaining < 0
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Overline(isOver ? "Over by" : "Left")
                MoneyText(
                    amount: status.remaining.magnitudeValue,
                    font: .display(34),
                    colored: isOver
                )
            }
            BudgetBar(progress: status.progress, height: 8)
            Rule()
            HStack(alignment: .top, spacing: 12) {
                detailStat("Limit", amount: status.limit)
                detailStat("Spent", amount: status.spent)
                if status.carriedOver != 0 {
                    detailStat("Carried", amount: status.carriedOver, signed: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibility(status: status))
    }

    private func unbudgetedBody(spent: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline("Spent")
            MoneyText(amount: spent, font: .display(34))
            Text("This category has no limit yet. Use Edit to set one.")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private func detailStat(_ title: String, amount: Decimal, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Overline(title)
            MoneyText(amount: amount, showsSign: signed, font: .amountSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerAccessibility(status: CategoryStatus) -> String {
        if settings.hideAmounts { return "\(category.name) budget, amounts hidden" }
        let left: String = settings.format(status.remaining.magnitudeValue)
        let lead: String = status.remaining < 0 ? "\(left) over" : "\(left) left"
        return "\(category.name): \(lead). Limit \(settings.format(status.limit)), spent \(settings.format(status.spent))."
    }

    // MARK: Transactions

    private func transactionsSection(rows: [Transaction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Transactions")
            if rows.isEmpty {
                Text("Nothing spent in this category during this period.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .tallyCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, transaction in
                        if index > 0 { Rule() }
                        Button {
                            editingTransaction = transaction
                        } label: {
                            BudgetTransactionRow(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .tallyCard(padding: 0)
            }
        }
    }
}

/// A single transaction line: title, date and amount.
struct BudgetTransactionRow: View {
    @Environment(AppSettings.self) private var settings
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.displayTitle)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(transaction.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 8)
            MoneyText(amount: transaction.amount, font: .amount)
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the transaction")
    }

    private var accessibilityText: String {
        let date: String = transaction.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if settings.hideAmounts { return "\(transaction.displayTitle), \(date), amount hidden" }
        return "\(transaction.displayTitle), \(date), \(settings.format(transaction.amount))"
    }
}
