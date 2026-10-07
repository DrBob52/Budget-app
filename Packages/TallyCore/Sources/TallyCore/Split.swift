import Foundation

public enum SplitMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case equal
    case exact
    case percentage
    case shares

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .equal: return String(localized: "Equally", bundle: .module)
        case .exact: return String(localized: "Exact amounts", bundle: .module)
        case .percentage: return String(localized: "Percentages", bundle: .module)
        case .shares: return String(localized: "Shares", bundle: .module)
        }
    }
}

/// An expense paid by one member and owed by one or more members.
public struct SharedExpense: Hashable, Sendable {
    public var amount: Decimal
    public var payerID: UUID
    /// What each member owes for this expense. Should sum to `amount`.
    public var owed: [UUID: Decimal]

    public init(amount: Decimal, payerID: UUID, owed: [UUID: Decimal]) {
        self.amount = amount
        self.payerID = payerID
        self.owed = owed
    }
}

/// A recorded repayment: `fromID` paid `toID`.
public struct SettlementRecord: Hashable, Sendable {
    public var fromID: UUID
    public var toID: UUID
    public var amount: Decimal

    public init(fromID: UUID, toID: UUID, amount: Decimal) {
        self.fromID = fromID
        self.toID = toID
        self.amount = amount
    }
}

/// A suggested payment that moves balances toward zero.
public struct SettleUpTransfer: Hashable, Identifiable, Sendable {
    public var fromID: UUID
    public var toID: UUID
    public var amount: Decimal
    public var id: String { "\(fromID)-\(toID)" }
}

public enum SplitCalculator {
    /// Splits `amount` evenly; leftover cents go to the first members in order.
    public static func equalShares(amount: Decimal, among memberIDs: [UUID], scale: Int = 2) -> [UUID: Decimal] {
        guard !memberIDs.isEmpty else { return [:] }
        let weights = Dictionary(uniqueKeysWithValues: memberIDs.map { ($0, Decimal(1)) })
        return weightedShares(amount: amount, weights: weights, order: memberIDs, scale: scale)
    }

    /// Splits `amount` by percentages (0...100). Percentages that don't sum to 100 are normalised.
    public static func percentageShares(amount: Decimal, percentages: [UUID: Decimal], order: [UUID]? = nil, scale: Int = 2) -> [UUID: Decimal] {
        weightedShares(amount: amount, weights: percentages, order: order, scale: scale)
    }

    /// Splits `amount` proportionally to `weights`, rounding to `scale` and fixing the remainder
    /// so the parts always add up to the original amount.
    public static func weightedShares(amount: Decimal, weights: [UUID: Decimal], order: [UUID]? = nil, scale: Int = 2) -> [UUID: Decimal] {
        let ids = (order ?? weights.keys.sorted { $0.uuidString < $1.uuidString }).filter { (weights[$0] ?? 0) > 0 }
        let totalWeight = ids.reduce(Decimal(0)) { $0 + (weights[$1] ?? 0) }
        guard totalWeight > 0 else { return [:] }

        let target = amount.rounded(scale: scale)
        var result: [UUID: Decimal] = [:]
        var assigned: Decimal = 0
        for id in ids {
            let share = (target * (weights[id] ?? 0) / totalWeight).rounded(scale: scale, mode: .down)
            result[id] = share
            assigned += share
        }

        let unit = Decimal.unit(scale: scale)
        var remainder = target - assigned
        var index = 0
        while remainder >= unit, !ids.isEmpty {
            result[ids[index % ids.count], default: 0] += unit
            remainder -= unit
            index += 1
        }
        return result
    }

    /// Net position per member: positive = others owe them, negative = they owe others.
    public static func netBalances(expenses: [SharedExpense], settlements: [SettlementRecord] = []) -> [UUID: Decimal] {
        var balances: [UUID: Decimal] = [:]
        for expense in expenses {
            balances[expense.payerID, default: 0] += expense.amount
            for (member, owed) in expense.owed {
                balances[member, default: 0] -= owed
            }
        }
        for settlement in settlements {
            balances[settlement.fromID, default: 0] += settlement.amount
            balances[settlement.toID, default: 0] -= settlement.amount
        }
        return balances
    }

    /// Fewest-ish payments to clear every balance: repeatedly match the largest debtor with the
    /// largest creditor.
    public static func settleUp(balances: [UUID: Decimal], scale: Int = 2) -> [SettleUpTransfer] {
        let unit = Decimal.unit(scale: scale)
        var debtors = balances.filter { $0.value <= -unit }.map { ($0.key, -$0.value) }
        var creditors = balances.filter { $0.value >= unit }.map { ($0.key, $0.value) }
        var transfers: [SettleUpTransfer] = []

        while !debtors.isEmpty, !creditors.isEmpty {
            debtors.sort { $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1 }
            creditors.sort { $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1 }
            let (debtor, owes) = debtors[0]
            let (creditor, owed) = creditors[0]
            let amount = min(owes, owed).rounded(scale: scale)
            if amount >= unit {
                transfers.append(SettleUpTransfer(fromID: debtor, toID: creditor, amount: amount))
            }
            let newOwes = owes - amount
            let newOwed = owed - amount
            if newOwes < unit { debtors.removeFirst() } else { debtors[0].1 = newOwes }
            if newOwed < unit { creditors.removeFirst() } else { creditors[0].1 = newOwed }
        }
        return transfers
    }
}
