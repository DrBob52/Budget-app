import Foundation
import SwiftUI
import TallyCore

// Plain-value inputs for the Insights cards. Everything is computed once per render
// from the TallyCore calculators so the card views stay small.

struct InsightsSlice: Identifiable, Hashable {
    let id: String
    let categoryID: UUID?
    let name: String
    let symbol: String
    let colorHex: String
    let amount: Decimal
    let share: Double
}

struct InsightsPacePoint: Identifiable, Hashable {
    let date: Date
    let cumulative: Double
    var id: Date { date }
}

struct InsightsNetWorthPoint: Identifiable, Hashable {
    let label: String
    let value: Decimal
    var id: String { label }
}

enum InsightsFormat {
    /// Short axis label: "Oct" for monthly budgets, "Oct 5" for weekly and two-week ones.
    static func shortLabel(_ period: BudgetPeriod, kind: PeriodKind) -> String {
        if kind == .monthly {
            return period.start.formatted(.dateTime.month(.abbreviated))
        }
        return period.start.formatted(.dateTime.month(.abbreviated).day())
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

struct InsightsData {
    static let historyCount = 6

    let period: BudgetPeriod
    let periodKind: PeriodKind
    /// The last six periods ending with the selected one, oldest first.
    let history: [PeriodTotals]
    let current: PeriodTotals
    let previous: PeriodTotals
    let averageSpending: Decimal
    let totalBudget: Decimal
    let slices: [InsightsSlice]
    let pacePoints: [InsightsPacePoint]
    let spentToDate: Decimal
    let elapsedDays: Int
    let daysInPeriod: Int
    let payees: [PayeeTotal]
    let netWorth: [InsightsNetWorthPoint]

    init(
        transactions: [Transaction],
        categories: [Category],
        accounts: [Account],
        period: BudgetPeriod,
        settings: AppSettings,
        now: Date = Date()
    ) {
        let calculator = settings.periodCalculator
        let entries: [LedgerEntry] = transactions.map(\.ledgerEntry)
        let periods: [BudgetPeriod] = calculator.periods(endingWith: period, count: InsightsData.historyCount)
        let totals: [PeriodTotals] = InsightsCalculator.periodTotals(entries: entries, periods: periods)

        self.period = period
        self.periodKind = settings.periodKind
        self.history = totals
        // PeriodTotals has no public initializer, so empty values come from the calculator.
        let emptyCurrent: PeriodTotals = InsightsCalculator.periodTotals(entries: [], periods: [period])[0]
        let emptyPrevious: PeriodTotals = InsightsCalculator.periodTotals(entries: [], periods: [calculator.period(before: period)])[0]
        self.current = totals.last ?? emptyCurrent
        self.previous = totals.count >= 2 ? totals[totals.count - 2] : emptyPrevious
        self.averageSpending = InsightsCalculator.averageExpenses(totals)
        self.daysInPeriod = period.dayCount(calendar: calculator.calendar)

        let summary: PeriodSummary = BudgetService.summary(
            for: period,
            transactions: transactions,
            categories: categories,
            settings: settings,
            now: now
        )
        self.totalBudget = summary.totalBudget

        // Spending by category.
        var byID: [UUID: Category] = [:]
        for category in categories { byID[category.id] = category }
        let categoryTotals: [CategoryTotal] = InsightsCalculator.totalsByCategory(entries: entries, in: period)
        var builtSlices: [InsightsSlice] = []
        for item in categoryTotals where item.total > 0 {
            let category: Category? = item.categoryID.flatMap { byID[$0] }
            builtSlices.append(InsightsSlice(
                id: item.id,
                categoryID: item.categoryID,
                name: category?.name ?? "Uncategorized",
                symbol: category?.symbol ?? "questionmark",
                colorHex: category?.colorHex ?? "#9C978C",
                amount: item.total,
                share: item.share
            ))
        }
        self.slices = builtSlices

        // Daily pace.
        let daily: [DailyPoint] = InsightsCalculator.dailySpending(
            entries: entries,
            in: period,
            now: now,
            calendar: calculator.calendar
        )
        self.pacePoints = daily.map { InsightsPacePoint(date: $0.date, cumulative: $0.cumulative.doubleValue) }
        self.spentToDate = daily.last?.cumulative ?? 0
        self.elapsedDays = daily.count

        self.payees = InsightsCalculator.topPayees(entries: entries, in: period, limit: 5)

        // Net worth at the end of each of the last periods.
        let counted: [Account] = accounts.filter { !$0.isArchived && $0.includeInNetWorth }
        var points: [InsightsNetWorthPoint] = []
        for item in periods {
            let periodEnd: Date = item.end.addingTimeInterval(-1)
            let asOf: Date = min(periodEnd, now)
            var total: Decimal = 0
            for account in counted {
                total += BalanceCalculator.balance(
                    accountID: account.id,
                    openingBalance: account.openingBalance,
                    entries: entries,
                    asOf: asOf
                )
            }
            points.append(InsightsNetWorthPoint(
                label: InsightsFormat.shortLabel(item, kind: settings.periodKind),
                value: total
            ))
        }
        self.netWorth = points
    }

    var hasSpending: Bool { current.expenses > 0 }

    /// What an even spend rate would have used so far. Nil without a budget.
    var expectedToDate: Decimal? {
        guard totalBudget > 0, daysInPeriod > 0 else { return nil }
        return totalBudget * Decimal(min(elapsedDays, daysInPeriod)) / Decimal(daysInPeriod)
    }

    func label(for totals: PeriodTotals) -> String {
        InsightsFormat.shortLabel(totals.period, kind: periodKind)
    }
}
