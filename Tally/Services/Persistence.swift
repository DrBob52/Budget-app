import Foundation
import SwiftData
import TallyCore

enum Persistence {
    /// Set to true once an iCloud container is configured in Signing & Capabilities to sync
    /// data across the user's own devices.
    static let cloudSyncEnabled = false

    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(TallySchema.models)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: cloudSyncEnabled ? .automatic : .none
            )
        }
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the Tally database: \(error)")
        }
    }

    /// In-memory container filled with sample data, for SwiftUI previews.
    @MainActor
    static let preview: ModelContainer = {
        let container = makeContainer(inMemory: true)
        SampleData.insert(into: container.mainContext)
        return container
    }()
}

/// Starter categories offered during onboarding and used for previews.
enum StarterCategories {
    struct Template: Identifiable, Hashable {
        /// English name; also the lookup key in the string catalog.
        let key: String
        let symbol: String
        let colorHex: String
        let kind: CategoryKind
        /// Suggested share of income for the default budget.
        let suggestedShare: Decimal

        init(name: String, symbol: String, colorHex: String, kind: CategoryKind, suggestedShare: Decimal) {
            self.key = name
            self.symbol = symbol
            self.colorHex = colorHex
            self.kind = kind
            self.suggestedShare = suggestedShare
        }

        /// Name in the user's language. Categories keep the name they were created with.
        var name: String { String(localized: String.LocalizationValue(key)) }
        var id: String { key }
    }

    static let expense: [Template] = [
        Template(name: "Rent & Housing", symbol: "house", colorHex: "#2F4B7C", kind: .expense, suggestedShare: Decimal(string: "0.30")!),
        Template(name: "Groceries", symbol: "cart", colorHex: "#2E6F5E", kind: .expense, suggestedShare: Decimal(string: "0.12")!),
        Template(name: "Dining Out", symbol: "fork.knife", colorHex: "#B84A26", kind: .expense, suggestedShare: Decimal(string: "0.06")!),
        Template(name: "Transport", symbol: "tram", colorHex: "#3E7C8C", kind: .expense, suggestedShare: Decimal(string: "0.06")!),
        Template(name: "Bills & Utilities", symbol: "bolt", colorHex: "#B7862B", kind: .expense, suggestedShare: Decimal(string: "0.08")!),
        Template(name: "Subscriptions", symbol: "repeat", colorHex: "#6B4E71", kind: .expense, suggestedShare: Decimal(string: "0.03")!),
        Template(name: "Shopping", symbol: "bag", colorHex: "#A23B57", kind: .expense, suggestedShare: Decimal(string: "0.05")!),
        Template(name: "Health", symbol: "cross.case", colorHex: "#5A6B2F", kind: .expense, suggestedShare: Decimal(string: "0.04")!),
        Template(name: "Entertainment", symbol: "theatermasks", colorHex: "#C07A2C", kind: .expense, suggestedShare: Decimal(string: "0.04")!),
        Template(name: "Travel", symbol: "airplane", colorHex: "#4A5560", kind: .expense, suggestedShare: Decimal(string: "0.05")!),
        Template(name: "Gifts", symbol: "gift", colorHex: "#8A5A44", kind: .expense, suggestedShare: Decimal(string: "0.02")!),
        Template(name: "Other", symbol: "ellipsis.circle", colorHex: "#6B675F", kind: .expense, suggestedShare: Decimal(string: "0.03")!)
    ]

    static let income: [Template] = [
        Template(name: "Salary", symbol: "briefcase", colorHex: "#1F5C4A", kind: .income, suggestedShare: 0),
        Template(name: "Side income", symbol: "sparkles", colorHex: "#2E6F5E", kind: .income, suggestedShare: 0),
        Template(name: "Refunds", symbol: "arrow.uturn.backward", colorHex: "#3E7C8C", kind: .income, suggestedShare: 0)
    ]
}

enum SampleData {
    /// Decimal from a string; float literals pick up binary rounding noise.
    static func dec(_ text: String) -> Decimal { Decimal(string: text) ?? 0 }

    @MainActor
    static func insert(into context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()

        var categories: [String: Category] = [:]
        for (index, template) in (StarterCategories.expense + StarterCategories.income).enumerated() {
            let limit = template.kind == .expense ? (Decimal(4000) * template.suggestedShare).rounded(scale: 0) : 0
            let category = Category(name: template.name, symbol: template.symbol, colorHex: template.colorHex, kind: template.kind, budgetLimit: limit, sortOrder: index)
            context.insert(category)
            categories[template.key] = category
        }

        let checking = Account(name: String(localized: "Everyday"), kind: .checking, openingBalance: 2_150, colorHex: "#2F4B7C")
        let savings = Account(name: String(localized: "Rainy day"), kind: .savings, openingBalance: 5_400, colorHex: "#1F5C4A", sortOrder: 1)
        let card = Account(name: "Visa", kind: .credit, openingBalance: 0, colorHex: "#A23B57", sortOrder: 2)
        [checking, savings, card].forEach(context.insert)

        func add(_ amount: Decimal, _ kind: TransactionKind, _ title: String, _ category: String, daysAgo: Int, account: Account? = nil) {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let transaction = Transaction(amount: amount, kind: kind, title: title, date: date, category: categories[category], account: account ?? checking)
            context.insert(transaction)
        }

        add(4_000, .income, "Acme Corp", "Salary", daysAgo: 5)
        add(1_200, .expense, "Landlord", "Rent & Housing", daysAgo: 4)
        add(dec("86.40"), .expense, "Green Grocer", "Groceries", daysAgo: 3)
        add(dec("54.10"), .expense, "Corner Market", "Groceries", daysAgo: 1)
        add(dec("38.00"), .expense, "Noodle Bar", "Dining Out", daysAgo: 2, account: card)
        add(dec("64.50"), .expense, "Bistro Nine", "Dining Out", daysAgo: 0, account: card)
        add(dec("45.00"), .expense, "Metro card", "Transport", daysAgo: 6)
        add(dec("15.99"), .expense, "StreamBox", "Subscriptions", daysAgo: 8, account: card)
        add(dec("92.30"), .expense, "City Power", "Bills & Utilities", daysAgo: 9)
        add(dec("120.00"), .expense, "Outdoor Co", "Shopping", daysAgo: 12, account: card)
        add(3_950, .income, "Acme Corp", "Salary", daysAgo: 35)
        add(1_200, .expense, "Landlord", "Rent & Housing", daysAgo: 34)
        add(dec("410.25"), .expense, "Green Grocer", "Groceries", daysAgo: 30)
        add(dec("180.00"), .expense, "Bistro Nine", "Dining Out", daysAgo: 28)
        add(dec("260.00"), .expense, "Weekend away", "Travel", daysAgo: 40)

        let subscription = RecurringTemplate(title: "StreamBox", amount: dec("15.99"), kind: .expense, frequency: .monthly, startDate: calendar.date(byAdding: .day, value: -8, to: now) ?? now, category: categories["Subscriptions"], account: card)
        subscription.lastGeneratedDate = subscription.startDate
        context.insert(subscription)

        let trip = SavingsGoal(name: String(localized: "Lisbon trip"), targetAmount: 1_800, symbol: "airplane", colorHex: "#C07A2C", deadline: calendar.date(byAdding: .month, value: 5, to: now))
        context.insert(trip)
        for (amount, daysAgo) in [(Decimal(300), 60), (Decimal(250), 30), (Decimal(200), 2)] {
            let contribution = GoalContribution(amount: amount, date: calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now)
            contribution.goal = trip
            context.insert(contribution)
        }
        let cushion = SavingsGoal(name: String(localized: "Emergency fund"), targetAmount: 10_000, symbol: "lifepreserver", colorHex: "#1F5C4A")
        context.insert(cushion)

        let me = Member(name: String(localized: "Me"), colorHex: "#1F5C4A", isMe: true)
        let sam = Member(name: "Sam Rivera", colorHex: "#6B4E71")
        context.insert(me)
        context.insert(sam)

        let dinner = Transaction(amount: 84, kind: .expense, title: String(localized: "Dinner with Sam"), date: calendar.date(byAdding: .day, value: -1, to: now) ?? now, category: categories["Dining Out"], account: checking)
        dinner.paidBy = me
        context.insert(dinner)
        for member in [me, sam] {
            let share = SplitShare(amount: 42, weight: 1, member: member)
            share.transaction = dinner
            context.insert(share)
        }

        try? context.save()
    }
}
