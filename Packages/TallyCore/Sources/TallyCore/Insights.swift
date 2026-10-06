import Foundation

public struct CategoryTotal: Hashable, Identifiable, Sendable {
    public var categoryID: UUID?
    public var total: Decimal
    /// Fraction of all spending in the range, 0...1.
    public var share: Double
    public var id: String { categoryID?.uuidString ?? "uncategorized" }
}

public struct PeriodTotals: Hashable, Identifiable, Sendable {
    public var period: BudgetPeriod
    public var income: Decimal
    public var expenses: Decimal
    public var net: Decimal { income - expenses }
    public var id: Date { period.start }
}

public struct DailyPoint: Hashable, Identifiable, Sendable {
    public var date: Date
    public var amount: Decimal
    public var cumulative: Decimal
    public var id: Date { date }
}

public struct PayeeTotal: Hashable, Identifiable, Sendable {
    public var title: String
    public var total: Decimal
    public var count: Int
    public var id: String { title }
}

public enum InsightsCalculator {
    public static func totalsByCategory(
        entries: [LedgerEntry],
        in period: BudgetPeriod,
        kind: TransactionKind = .expense
    ) -> [CategoryTotal] {
        var totals: [UUID?: Decimal] = [:]
        for entry in entries where entry.kind == kind && period.contains(entry.date) {
            totals[entry.categoryID, default: 0] += entry.amount
        }
        let sum = totals.values.reduce(Decimal(0), +)
        return totals
            .map { CategoryTotal(categoryID: $0.key, total: $0.value, share: sum > 0 ? ($0.value / sum).doubleValue : 0) }
            .sorted { $0.total > $1.total }
    }

    public static func periodTotals(entries: [LedgerEntry], periods: [BudgetPeriod]) -> [PeriodTotals] {
        periods.map { period in
            var income: Decimal = 0
            var expenses: Decimal = 0
            for entry in entries where period.contains(entry.date) {
                if entry.kind == .income { income += entry.amount }
                if entry.kind == .expense { expenses += entry.amount }
            }
            return PeriodTotals(period: period, income: income, expenses: expenses)
        }
    }

    /// One point per day of the period with running expense totals. Days after `now` are omitted.
    public static func dailySpending(
        entries: [LedgerEntry],
        in period: BudgetPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyPoint] {
        var byDay: [Date: Decimal] = [:]
        for entry in entries where entry.kind == .expense && period.contains(entry.date) {
            byDay[calendar.startOfDay(for: entry.date), default: 0] += entry.amount
        }
        var points: [DailyPoint] = []
        var running: Decimal = 0
        var day = period.start
        let stop = min(period.end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? period.end)
        while day < stop {
            let amount = byDay[day] ?? 0
            running += amount
            points.append(DailyPoint(date: day, amount: amount, cumulative: running))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    public static func topPayees(entries: [LedgerEntry], in period: BudgetPeriod, limit: Int = 5) -> [PayeeTotal] {
        var totals: [String: (Decimal, Int, String)] = [:]
        for entry in entries where entry.kind == .expense && period.contains(entry.date) {
            let display = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            let key = display.lowercased()
            let current = totals[key] ?? (0, 0, display)
            totals[key] = (current.0 + entry.amount, current.1 + 1, current.2)
        }
        return totals.values
            .map { PayeeTotal(title: $0.2, total: $0.0, count: $0.1) }
            .sorted { $0.total > $1.total }
            .prefix(limit)
            .map { $0 }
    }

    /// Portion of income not spent, nil without income.
    public static func savingsRate(income: Decimal, expenses: Decimal) -> Double? {
        guard income > 0 else { return nil }
        return ((income - expenses) / income).doubleValue
    }

    /// Average expenses across the given periods.
    public static func averageExpenses(_ totals: [PeriodTotals]) -> Decimal {
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(Decimal(0)) { $0 + $1.expenses } / Decimal(totals.count)
    }
}
