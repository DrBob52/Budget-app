import Foundation
import SwiftData
import TallyCore
import WidgetKit

/// Bridges SwiftData models to the TallyCore calculators.
enum BudgetService {
    static func summary(
        for period: BudgetPeriod,
        transactions: [Transaction],
        categories: [Category],
        settings: AppSettings,
        now: Date = Date()
    ) -> PeriodSummary {
        BudgetCalculator.summary(
            for: period,
            entries: transactions.map(\.ledgerEntry),
            budgets: categories.filter { !$0.isArchived && $0.kind == .expense }.map(\.budget),
            calculator: settings.periodCalculator,
            rolloverEnabled: settings.rolloverEnabled,
            now: now
        )
    }

    /// Net worth across accounts flagged for it. Credit balances are usually negative already.
    static func netWorth(accounts: [Account]) -> Decimal {
        accounts
            .filter { !$0.isArchived && $0.includeInNetWorth }
            .reduce(Decimal(0)) { $0 + $1.balance }
    }

    /// Net positions for everyone in a shared budget (positive = is owed money).
    static func memberBalances(transactions: [Transaction], settlements: [Settlement]) -> [UUID: Decimal] {
        SplitCalculator.netBalances(
            expenses: transactions.compactMap(\.sharedExpense),
            settlements: settlements.compactMap(\.record)
        )
    }
}

/// Writes the widget / watch snapshot and refreshes widgets.
enum SnapshotService {
    @MainActor
    static func refresh(context: ModelContext, settings: AppSettings) {
        guard let snapshot = makeSnapshot(context: context, settings: settings) else { return }
        if let directory = SnapshotStore.sharedDirectory {
            try? SnapshotStore.write(snapshot, to: directory)
        }
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .budgetSnapshotDidChange, object: snapshot)
    }

    @MainActor
    static func makeSnapshot(context: ModelContext, settings: AppSettings, now: Date = Date()) -> BudgetSnapshot? {
        let period = settings.periodCalculator.period(containing: now)
        guard let categories = try? context.fetch(FetchDescriptor<Category>()) else { return nil }
        // Rollover needs earlier periods, so fetch a year back.
        let since = Calendar.current.date(byAdding: .year, value: -1, to: period.start) ?? period.start
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= since })
        guard let transactions = try? context.fetch(descriptor) else { return nil }

        let summary = BudgetService.summary(for: period, transactions: transactions, categories: categories, settings: settings, now: now)
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        let lines = summary.categoryStatuses
            .sorted { $0.spent > $1.spent }
            .compactMap { status -> BudgetSnapshot.CategoryLine? in
                guard let category = byID[status.id] else { return nil }
                return BudgetSnapshot.CategoryLine(
                    id: category.id,
                    name: category.name,
                    symbol: category.symbol,
                    colorHex: category.colorHex,
                    spent: status.spent,
                    available: status.available
                )
            }

        let quick = categories
            .filter { !$0.isArchived && $0.kind == .expense }
            .sorted { $0.sortOrder < $1.sortOrder }
            .prefix(8)
            .map { BudgetSnapshot.QuickCategory(id: $0.id, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex) }

        return BudgetSnapshot(
            currencyCode: settings.currencyCode,
            periodTitle: period.title(),
            periodStart: period.start,
            periodEnd: period.end,
            totalBudget: summary.totalBudget,
            spent: summary.expenses,
            income: summary.income,
            leftToSpend: summary.leftToSpend,
            dailyAllowance: summary.dailyAllowance,
            daysRemaining: summary.daysRemaining,
            categories: lines,
            quickCategories: Array(quick),
            updatedAt: now
        )
    }
}

extension Notification.Name {
    /// Posted with the new `BudgetSnapshot` as object; the watch connector forwards it.
    static let budgetSnapshotDidChange = Notification.Name("budgetSnapshotDidChange")
}
