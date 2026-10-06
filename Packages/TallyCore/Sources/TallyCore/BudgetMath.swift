import Foundation

public enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income
    case transfer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        }
    }
}

/// A plain-value view of a transaction, used by all calculations.
public struct LedgerEntry: Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Always positive. `kind` gives the direction.
    public var amount: Decimal
    public var kind: TransactionKind
    public var date: Date
    public var categoryID: UUID?
    public var accountID: UUID?
    public var toAccountID: UUID?
    public var title: String

    public init(
        id: UUID = UUID(),
        amount: Decimal,
        kind: TransactionKind,
        date: Date,
        categoryID: UUID? = nil,
        accountID: UUID? = nil,
        toAccountID: UUID? = nil,
        title: String = ""
    ) {
        self.id = id
        self.amount = amount
        self.kind = kind
        self.date = date
        self.categoryID = categoryID
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.title = title
    }
}

public struct CategoryBudget: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Spending limit per period. Zero means the category has no budget.
    public var limit: Decimal
    public var rollsOver: Bool

    public init(id: UUID, name: String, limit: Decimal, rollsOver: Bool = false) {
        self.id = id
        self.name = name
        self.limit = limit
        self.rollsOver = rollsOver
    }
}

public struct CategoryStatus: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var limit: Decimal
    /// Leftover (or overspend, when negative) carried in from earlier periods.
    public var carriedOver: Decimal
    public var spent: Decimal

    public var available: Decimal { limit + carriedOver }
    public var remaining: Decimal { available - spent }
    public var isOver: Bool { spent > available }

    /// Share of the available amount already spent. Can exceed 1.
    public var progress: Double {
        guard available > 0 else { return spent > 0 ? 1 : 0 }
        return (spent / available).doubleValue
    }
}

public struct PeriodSummary: Sendable {
    public var period: BudgetPeriod
    public var income: Decimal
    public var expenses: Decimal
    /// Sum of every budgeted category's available amount (limit + carry-over).
    public var totalBudget: Decimal
    /// Expenses that landed in budgeted categories.
    public var budgetedSpent: Decimal
    /// Expenses in categories without a limit, or with no category.
    public var unbudgetedSpent: Decimal
    public var categoryStatuses: [CategoryStatus]
    /// Expense totals keyed by category; `nil` key = uncategorized.
    public var spentByCategory: [UUID?: Decimal]
    /// Days left in the period counting today (0 for past periods).
    public var daysRemaining: Int

    /// Budget left after every expense this period, budgeted or not.
    public var leftToSpend: Decimal { totalBudget - expenses }
    public var net: Decimal { income - expenses }

    /// How much can be spent per day for the rest of the period, nil when not meaningful.
    public var dailyAllowance: Decimal? {
        guard daysRemaining > 0, totalBudget > 0 else { return nil }
        return max(leftToSpend, 0) / Decimal(daysRemaining)
    }

    public func status(for categoryID: UUID) -> CategoryStatus? {
        categoryStatuses.first { $0.id == categoryID }
    }
}

public enum BudgetCalculator {
    /// Expense totals per category within `period`.
    public static func spending(in period: BudgetPeriod, entries: [LedgerEntry]) -> [UUID?: Decimal] {
        var totals: [UUID?: Decimal] = [:]
        for entry in entries where entry.kind == .expense && period.contains(entry.date) {
            totals[entry.categoryID, default: 0] += entry.amount
        }
        return totals
    }

    /// Builds the full budget picture for one period.
    /// - Parameters:
    ///   - rolloverEnabled: global switch; individual categories also need `rollsOver`.
    ///   - rolloverLookback: max number of earlier periods to carry from.
    public static func summary(
        for period: BudgetPeriod,
        entries: [LedgerEntry],
        budgets: [CategoryBudget],
        calculator: PeriodCalculator,
        rolloverEnabled: Bool,
        rolloverLookback: Int = 12,
        now: Date = Date()
    ) -> PeriodSummary {
        let spent = spending(in: period, entries: entries)
        let earliest = entries.map(\.date).min()

        var statuses: [CategoryStatus] = []
        var budgetedIDs = Set<UUID>()
        for budget in budgets where budget.limit > 0 {
            budgetedIDs.insert(budget.id)
            var carry: Decimal = 0
            if rolloverEnabled, budget.rollsOver, let earliest {
                carry = carryOver(
                    into: period,
                    budget: budget,
                    entries: entries,
                    calculator: calculator,
                    earliest: earliest,
                    lookback: rolloverLookback
                )
            }
            statuses.append(CategoryStatus(
                id: budget.id,
                limit: budget.limit,
                carriedOver: carry,
                spent: spent[budget.id] ?? 0
            ))
        }

        var income: Decimal = 0
        var expenses: Decimal = 0
        for entry in entries where period.contains(entry.date) {
            switch entry.kind {
            case .income: income += entry.amount
            case .expense: expenses += entry.amount
            case .transfer: break
            }
        }

        let budgetedSpent = statuses.reduce(Decimal(0)) { $0 + $1.spent }
        let totalBudget = statuses.reduce(Decimal(0)) { $0 + $1.available }

        return PeriodSummary(
            period: period,
            income: income,
            expenses: expenses,
            totalBudget: totalBudget,
            budgetedSpent: budgetedSpent,
            unbudgetedSpent: expenses - budgetedSpent,
            categoryStatuses: statuses,
            spentByCategory: spent,
            daysRemaining: period.daysRemaining(from: now, calendar: calculator.calendar)
        )
    }

    /// Leftover carried into `period`: for each earlier period since the user's first entry,
    /// carry = carry + limit - spent. Overspending carries forward as a negative amount.
    static func carryOver(
        into period: BudgetPeriod,
        budget: CategoryBudget,
        entries: [LedgerEntry],
        calculator: PeriodCalculator,
        earliest: Date,
        lookback: Int
    ) -> Decimal {
        guard earliest < period.start, lookback > 0 else { return 0 }
        let earlier = calculator.periods(
            endingWith: calculator.period(before: period),
            count: lookback
        ).filter { $0.end > earliest }

        var carry: Decimal = 0
        for previous in earlier {
            let spentThen = entries.reduce(Decimal(0)) { total, entry in
                guard entry.kind == .expense,
                      entry.categoryID == budget.id,
                      previous.contains(entry.date) else { return total }
                return total + entry.amount
            }
            carry = carry + budget.limit - spentThen
        }
        return carry
    }
}

public enum BalanceCalculator {
    /// Current balance of an account given its opening balance and every entry touching it.
    public static func balance(accountID: UUID, openingBalance: Decimal, entries: [LedgerEntry], asOf: Date? = nil) -> Decimal {
        var balance = openingBalance
        for entry in entries {
            if let asOf, entry.date > asOf { continue }
            switch entry.kind {
            case .income where entry.accountID == accountID:
                balance += entry.amount
            case .expense where entry.accountID == accountID:
                balance -= entry.amount
            case .transfer:
                if entry.accountID == accountID { balance -= entry.amount }
                if entry.toAccountID == accountID { balance += entry.amount }
            default:
                break
            }
        }
        return balance
    }
}
