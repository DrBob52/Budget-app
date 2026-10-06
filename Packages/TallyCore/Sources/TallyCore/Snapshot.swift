import Foundation

/// A small, precomputed picture of the current budget that the widget and watch app render
/// without opening the database.
public struct BudgetSnapshot: Codable, Equatable, Sendable {
    public struct CategoryLine: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var symbol: String
        public var colorHex: String
        public var spent: Decimal
        public var available: Decimal

        public init(id: UUID, name: String, symbol: String, colorHex: String, spent: Decimal, available: Decimal) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.colorHex = colorHex
            self.spent = spent
            self.available = available
        }

        public var progress: Double {
            guard available > 0 else { return spent > 0 ? 1 : 0 }
            return (spent / available).doubleValue
        }
    }

    public struct QuickCategory: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var symbol: String
        public var colorHex: String

        public init(id: UUID, name: String, symbol: String, colorHex: String) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.colorHex = colorHex
        }
    }

    public var currencyCode: String
    public var periodTitle: String
    public var periodStart: Date
    public var periodEnd: Date
    public var totalBudget: Decimal
    public var spent: Decimal
    public var income: Decimal
    public var leftToSpend: Decimal
    public var dailyAllowance: Decimal?
    public var daysRemaining: Int
    /// Budgeted categories, most-used first.
    public var categories: [CategoryLine]
    /// Expense categories offered for quick logging on the watch.
    public var quickCategories: [QuickCategory]
    public var updatedAt: Date

    public init(
        currencyCode: String,
        periodTitle: String,
        periodStart: Date,
        periodEnd: Date,
        totalBudget: Decimal,
        spent: Decimal,
        income: Decimal,
        leftToSpend: Decimal,
        dailyAllowance: Decimal?,
        daysRemaining: Int,
        categories: [CategoryLine],
        quickCategories: [QuickCategory],
        updatedAt: Date
    ) {
        self.currencyCode = currencyCode
        self.periodTitle = periodTitle
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.totalBudget = totalBudget
        self.spent = spent
        self.income = income
        self.leftToSpend = leftToSpend
        self.dailyAllowance = dailyAllowance
        self.daysRemaining = daysRemaining
        self.categories = categories
        self.quickCategories = quickCategories
        self.updatedAt = updatedAt
    }

    public var progress: Double {
        guard totalBudget > 0 else { return 0 }
        return (spent / totalBudget).doubleValue
    }

    public static let placeholder = BudgetSnapshot(
        currencyCode: "USD",
        periodTitle: "October 2026",
        periodStart: Date(),
        periodEnd: Date().addingTimeInterval(86_400 * 30),
        totalBudget: 2_400,
        spent: 1_310,
        income: 3_200,
        leftToSpend: 1_090,
        dailyAllowance: 54.5,
        daysRemaining: 20,
        categories: [
            CategoryLine(id: UUID(), name: "Groceries", symbol: "cart", colorHex: "#2E6F5E", spent: 420, available: 600),
            CategoryLine(id: UUID(), name: "Dining", symbol: "fork.knife", colorHex: "#B84A26", spent: 260, available: 250),
            CategoryLine(id: UUID(), name: "Transport", symbol: "tram", colorHex: "#2F4B7C", spent: 90, available: 150)
        ],
        quickCategories: [],
        updatedAt: Date()
    )
}

public enum SnapshotStore {
    public static let fileName = "budget-snapshot.json"

    public static func url(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public static func write(_ snapshot: BudgetSnapshot, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url(in: directory), options: .atomic)
    }

    public static func read(from directory: URL) -> BudgetSnapshot? {
        guard let data = try? Data(contentsOf: url(in: directory)) else { return nil }
        return decode(data)
    }

    public static func encode(_ snapshot: BudgetSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) -> BudgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BudgetSnapshot.self, from: data)
    }

    /// The shared App Group folder, when the entitlement is present.
    public static var sharedDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    }
}
