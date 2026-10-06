import Foundation
import SwiftData
import TallyCore

// All models keep default values and optional relationships so the store stays
// compatible with CloudKit sync.

enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
    var displayName: String { self == .expense ? "Expense" : "Income" }
}

enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case cash
    case checking
    case savings
    case credit
    case investment
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash: return "Cash"
        case .checking: return "Checking"
        case .savings: return "Savings"
        case .credit: return "Credit card"
        case .investment: return "Investments"
        case .other: return "Other"
        }
    }

    var defaultSymbol: String {
        switch self {
        case .cash: return "banknote"
        case .checking: return "building.columns"
        case .savings: return "archivebox"
        case .credit: return "creditcard"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .other: return "wallet.pass"
        }
    }

    /// Credit balances count against net worth.
    var isLiability: Bool { self == .credit }
}

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    /// SF Symbol name.
    var symbol: String = "tag"
    var colorHex: String = "#1F5C4A"
    var kindRaw: String = CategoryKind.expense.rawValue
    /// Spending limit per budget period. Zero = not budgeted.
    var budgetLimit: Decimal = 0
    /// Unspent budget carries into the next period when rollover is on in settings.
    var rollsOver: Bool = false
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringTemplate.category)
    var recurringTemplates: [RecurringTemplate]? = []

    init(name: String, symbol: String, colorHex: String, kind: CategoryKind = .expense, budgetLimit: Decimal = 0, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.budgetLimit = budgetLimit
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var isBudgeted: Bool { budgetLimit > 0 }

    var budget: CategoryBudget {
        CategoryBudget(id: id, name: name, limit: budgetLimit, rollsOver: rollsOver)
    }
}

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = AccountKind.checking.rawValue
    var symbol: String = "building.columns"
    var colorHex: String = "#2F4B7C"
    /// Balance on the day the account was added to Tally.
    var openingBalance: Decimal = 0
    var includeInNetWorth: Bool = true
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \Transaction.toAccount)
    var incomingTransfers: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringTemplate.account)
    var recurringTemplates: [RecurringTemplate]? = []

    init(name: String, kind: AccountKind, openingBalance: Decimal = 0, colorHex: String = "#2F4B7C", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.symbol = kind.defaultSymbol
        self.colorHex = colorHex
        self.openingBalance = openingBalance
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    /// Opening balance plus every income, expense and transfer touching this account.
    var balance: Decimal {
        var total = openingBalance
        for transaction in transactions ?? [] {
            switch transaction.kind {
            case .income: total += transaction.amount
            case .expense, .transfer: total -= transaction.amount
            }
        }
        for transfer in incomingTransfers ?? [] where transfer.kind == .transfer {
            total += transfer.amount
        }
        return total
    }
}

@Model
final class Transaction {
    var id: UUID = UUID()
    /// Always positive; `kind` gives the direction.
    var amount: Decimal = 0
    var kindRaw: String = TransactionKind.expense.rawValue
    var title: String = ""
    var note: String = ""
    var date: Date = Date()
    var createdAt: Date = Date()
    /// Set for rows that came from a bank statement, to skip duplicates on re-import.
    var importFingerprint: String?
    var splitMethodRaw: String = SplitMethod.equal.rawValue

    var category: Category?
    /// Source account. For transfers, money leaves this account.
    var account: Account?
    /// Destination account, transfers only.
    var toAccount: Account?
    /// Who paid, when the budget is shared. Nil = me / not shared.
    var paidBy: Member?
    var recurringTemplate: RecurringTemplate?

    @Relationship(deleteRule: .cascade, inverse: \SplitShare.transaction)
    var splitShares: [SplitShare]? = []

    init(amount: Decimal, kind: TransactionKind, title: String = "", date: Date = Date(), category: Category? = nil, account: Account? = nil, note: String = "") {
        self.id = UUID()
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.title = title
        self.date = date
        self.category = category
        self.account = account
        self.note = note
        self.createdAt = Date()
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var splitMethod: SplitMethod {
        get { SplitMethod(rawValue: splitMethodRaw) ?? .equal }
        set { splitMethodRaw = newValue.rawValue }
    }

    var isSplit: Bool { !(splitShares ?? []).isEmpty }

    /// Title to show in lists: the payee, else the category, else the kind.
    var displayTitle: String {
        if !title.isEmpty { return title }
        if let category { return category.name }
        return kind.displayName
    }

    var ledgerEntry: LedgerEntry {
        LedgerEntry(
            id: id,
            amount: amount,
            kind: kind,
            date: date,
            categoryID: category?.id,
            accountID: account?.id,
            toAccountID: toAccount?.id,
            title: title
        )
    }

    /// Split data for balance calculations, nil when not split.
    var sharedExpense: SharedExpense? {
        guard kind == .expense, let payer = paidBy, let shares = splitShares, !shares.isEmpty else { return nil }
        var owed: [UUID: Decimal] = [:]
        for share in shares {
            if let member = share.member {
                owed[member.id, default: 0] += share.amount
            }
        }
        return SharedExpense(amount: amount, payerID: payer.id, owed: owed)
    }
}

@Model
final class RecurringTemplate {
    var id: UUID = UUID()
    var title: String = ""
    var amount: Decimal = 0
    var kindRaw: String = TransactionKind.expense.rawValue
    var note: String = ""
    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    var startDate: Date = Date()
    var endDate: Date?
    /// Date of the last occurrence turned into a transaction.
    var lastGeneratedDate: Date?
    var isActive: Bool = true
    /// Remind the user the day before it's due (bills and subscriptions).
    var remindBeforeDue: Bool = false
    var createdAt: Date = Date()

    var category: Category?
    var account: Account?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.recurringTemplate)
    var transactions: [Transaction]? = []

    init(title: String, amount: Decimal, kind: TransactionKind, frequency: RecurrenceFrequency, startDate: Date, category: Category? = nil, account: Account? = nil) {
        self.id = UUID()
        self.title = title
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
        self.category = category
        self.account = account
        self.createdAt = Date()
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var rule: RecurrenceRule {
        RecurrenceRule(frequency: frequency, startDate: startDate, endDate: endDate)
    }

    var nextDueDate: Date? {
        rule.nextOccurrence(after: lastGeneratedDate ?? startDate.addingTimeInterval(-1))
    }
}

@Model
final class SavingsGoal {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "star"
    var colorHex: String = "#B7862B"
    var targetAmount: Decimal = 0
    var deadline: Date?
    var note: String = ""
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \GoalContribution.goal)
    var contributions: [GoalContribution]? = []

    init(name: String, targetAmount: Decimal, symbol: String = "star", colorHex: String = "#B7862B", deadline: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.targetAmount = targetAmount
        self.symbol = symbol
        self.colorHex = colorHex
        self.deadline = deadline
        self.createdAt = Date()
    }

    var savedAmount: Decimal {
        (contributions ?? []).reduce(Decimal(0)) { $0 + $1.amount }
    }

    var remainingAmount: Decimal { max(targetAmount - savedAmount, 0) }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min((savedAmount / targetAmount).doubleValue, 1)
    }

    var isComplete: Bool { targetAmount > 0 && savedAmount >= targetAmount }
}

@Model
final class GoalContribution {
    var id: UUID = UUID()
    /// Positive = deposit, negative = withdrawal.
    var amount: Decimal = 0
    var date: Date = Date()
    var note: String = ""
    var goal: SavingsGoal?

    init(amount: Decimal, date: Date = Date(), note: String = "") {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.note = note
    }
}

/// A person the budget is shared or split with. Exactly one member has `isMe == true`
/// once sharing is set up.
@Model
final class Member {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#6B4E71"
    var isMe: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Transaction.paidBy)
    var paidTransactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade, inverse: \SplitShare.member)
    var shares: [SplitShare]? = []

    @Relationship(deleteRule: .cascade, inverse: \Settlement.from)
    var settlementsSent: [Settlement]? = []

    @Relationship(deleteRule: .cascade, inverse: \Settlement.to)
    var settlementsReceived: [Settlement]? = []

    init(name: String, colorHex: String = "#6B4E71", isMe: Bool = false) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.isMe = isMe
        self.createdAt = Date()
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

/// The part of a split transaction one member owes.
@Model
final class SplitShare {
    var id: UUID = UUID()
    var amount: Decimal = 0
    /// Raw input for percentage / shares methods, so the editor can show it again.
    var weight: Decimal = 0
    var member: Member?
    var transaction: Transaction?

    init(amount: Decimal, weight: Decimal = 0, member: Member? = nil) {
        self.id = UUID()
        self.amount = amount
        self.weight = weight
        self.member = member
    }
}

/// A repayment between two members.
@Model
final class Settlement {
    var id: UUID = UUID()
    var amount: Decimal = 0
    var date: Date = Date()
    var note: String = ""
    var from: Member?
    var to: Member?

    init(amount: Decimal, from: Member?, to: Member?, date: Date = Date(), note: String = "") {
        self.id = UUID()
        self.amount = amount
        self.from = from
        self.to = to
        self.date = date
        self.note = note
    }

    var record: SettlementRecord? {
        guard let from, let to else { return nil }
        return SettlementRecord(fromID: from.id, toID: to.id, amount: amount)
    }
}

enum TallySchema {
    static let models: [any PersistentModel.Type] = [
        Category.self,
        Account.self,
        Transaction.self,
        RecurringTemplate.self,
        SavingsGoal.self,
        GoalContribution.self,
        Member.self,
        SplitShare.self,
        Settlement.self
    ]
}
