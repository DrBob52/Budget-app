import XCTest
import SwiftData
import TallyCore
@testable import Tally

// Outside the app module `Category` also names the Objective-C runtime type, so the
// SwiftData models are qualified with the module name here.
@MainActor
final class TallyTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = Persistence.makeContainer(inMemory: true)
    }

    override func tearDown() async throws {
        container = nil
    }

    func testSampleDataInserts() throws {
        SampleData.insert(into: context)
        let categories = try context.fetch(FetchDescriptor<Tally.Category>())
        let transactions = try context.fetch(FetchDescriptor<Tally.Transaction>())
        XCTAssertFalse(categories.isEmpty)
        XCTAssertFalse(transactions.isEmpty)
    }

    func testRecurringServiceGeneratesEachDueOccurrenceOnce() throws {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -15, to: now)!
        let template = RecurringTemplate(title: "Gym", amount: 30, kind: .expense, frequency: .weekly, startDate: start)
        context.insert(template)
        try context.save()

        RecurringService.generateDueTransactions(in: context, now: now)
        let firstPass = try context.fetch(FetchDescriptor<Tally.Transaction>())
        // Occurrences at day -15, -8 and -1.
        XCTAssertEqual(firstPass.count, 3)
        XCTAssertTrue(firstPass.allSatisfy { $0.recurringTemplate?.id == template.id })

        RecurringService.generateDueTransactions(in: context, now: now)
        let secondPass = try context.fetch(FetchDescriptor<Tally.Transaction>())
        XCTAssertEqual(secondPass.count, 3, "Running again must not duplicate transactions")
    }

    func testAccountBalanceIncludesTransfers() throws {
        let checking = Account(name: "Checking", kind: .checking, openingBalance: 1_000)
        let savings = Account(name: "Savings", kind: .savings, openingBalance: 0)
        context.insert(checking)
        context.insert(savings)

        let pay = Tally.Transaction(amount: 500, kind: .income, account: checking)
        let coffee = Tally.Transaction(amount: 20, kind: .expense, account: checking)
        let transfer = Tally.Transaction(amount: 200, kind: .transfer, account: checking)
        transfer.toAccount = savings
        [pay, coffee, transfer].forEach(context.insert)
        try context.save()

        XCTAssertEqual(checking.balance, 1_280)
        XCTAssertEqual(savings.balance, 200)
        XCTAssertEqual(BudgetService.netWorth(accounts: [checking, savings]), 1_480)
    }

    func testSummaryCountsBudgetedAndUnbudgetedSpending() throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "TallyTests.\(UUID().uuidString)")!)
        let groceries = Tally.Category(name: "Groceries", symbol: "cart", colorHex: "#2E6F5E", budgetLimit: 300)
        let gifts = Tally.Category(name: "Gifts", symbol: "gift", colorHex: "#8A5A44")
        context.insert(groceries)
        context.insert(gifts)
        let now = Date()
        let transactions = [
            Tally.Transaction(amount: 120, kind: .expense, date: now, category: groceries),
            Tally.Transaction(amount: 45, kind: .expense, date: now, category: gifts),
            Tally.Transaction(amount: 2_000, kind: .income, date: now)
        ]
        transactions.forEach(context.insert)
        try context.save()

        let summary = BudgetService.summary(
            for: settings.currentPeriod,
            transactions: transactions,
            categories: [groceries, gifts],
            settings: settings,
            now: now
        )
        XCTAssertEqual(summary.totalBudget, 300)
        XCTAssertEqual(summary.budgetedSpent, 120)
        XCTAssertEqual(summary.unbudgetedSpent, 45)
        XCTAssertEqual(summary.leftToSpend, 135)
        XCTAssertEqual(summary.income, 2_000)
    }

    func testMemberBalancesFromSplitExpense() throws {
        let me = Member(name: "Me", isMe: true)
        let sam = Member(name: "Sam")
        context.insert(me)
        context.insert(sam)
        let dinner = Tally.Transaction(amount: 84, kind: .expense, title: "Dinner")
        dinner.paidBy = me
        context.insert(dinner)
        for member in [me, sam] {
            let share = SplitShare(amount: 42, weight: 1, member: member)
            share.transaction = dinner
            context.insert(share)
        }
        try context.save()

        var balances = BudgetService.memberBalances(transactions: [dinner], settlements: [])
        XCTAssertEqual(balances[me.id], 42)
        XCTAssertEqual(balances[sam.id], -42)

        let repayment = Settlement(amount: 42, from: sam, to: me)
        context.insert(repayment)
        balances = BudgetService.memberBalances(transactions: [dinner], settlements: [repayment])
        XCTAssertEqual(balances[me.id], 0)
        XCTAssertEqual(balances[sam.id], 0)
    }

    func testDeepLinksRoute() {
        let router = AppRouter()
        router.handle(URL(string: "tally://add?kind=income")!)
        XCTAssertEqual(router.sheet, .addTransaction(.income))
        router.handle(URL(string: "tally://tab/insights")!)
        XCTAssertEqual(router.selectedTab, .insights)
        XCTAssertNil(router.sheet)
    }
}
