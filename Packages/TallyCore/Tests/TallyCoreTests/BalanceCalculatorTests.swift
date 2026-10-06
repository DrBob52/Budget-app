import XCTest
@testable import TallyCore

final class BalanceCalculatorTests: XCTestCase {
    private let checking = uuid(1)
    private let savings = uuid(2)
    private let stranger = uuid(3)

    func testOpeningBalanceOnlyWhenNoEntries() {
        XCTAssertEqual(BalanceCalculator.balance(accountID: checking, openingBalance: dec("250.75"), entries: []), dec("250.75"))
    }

    func testIncomeAddsAndExpenseSubtracts() {
        let entries = [
            makeEntry("500", .income, on: date(2026, 1, 5), account: checking),
            makeEntry("120.25", .expense, on: date(2026, 1, 6), account: checking)
        ]
        XCTAssertEqual(
            BalanceCalculator.balance(accountID: checking, openingBalance: dec("1000"), entries: entries),
            dec("1379.75")
        )
    }

    func testEntriesOfOtherAccountsAreIgnored() {
        let entries = [
            makeEntry("500", .income, on: date(2026, 1, 5), account: savings),
            makeEntry("70", .expense, on: date(2026, 1, 6), account: savings),
            makeEntry("10", .income, on: date(2026, 1, 7), account: nil)
        ]
        XCTAssertEqual(BalanceCalculator.balance(accountID: checking, openingBalance: dec("100"), entries: entries), dec("100"))
    }

    func testTransferMovesMoneyFromSourceToDestination() {
        let entries = [makeEntry("300", .transfer, on: date(2026, 1, 5), account: checking, to: savings)]
        XCTAssertEqual(BalanceCalculator.balance(accountID: checking, openingBalance: dec("1000"), entries: entries), dec("700"))
        XCTAssertEqual(BalanceCalculator.balance(accountID: savings, openingBalance: dec("50"), entries: entries), dec("350"))
        XCTAssertEqual(BalanceCalculator.balance(accountID: stranger, openingBalance: dec("50"), entries: entries), dec("50"))
    }

    func testTransferInAndOutCombined() {
        let entries = [
            makeEntry("300", .transfer, on: date(2026, 1, 5), account: checking, to: savings),
            makeEntry("100", .transfer, on: date(2026, 1, 8), account: savings, to: checking),
            makeEntry("500", .income, on: date(2026, 1, 9), account: checking),
            makeEntry("200", .expense, on: date(2026, 1, 10), account: checking),
            makeEntry("50", .expense, on: date(2026, 1, 11), account: savings),
            makeEntry("20", .income, on: date(2026, 1, 12), account: savings)
        ]
        XCTAssertEqual(BalanceCalculator.balance(accountID: checking, openingBalance: dec("1000"), entries: entries), dec("1100"))
        XCTAssertEqual(BalanceCalculator.balance(accountID: savings, openingBalance: 0, entries: entries), dec("170"))
    }

    func testTransfersBetweenTwoAccountsConserveMoney() {
        let entries = [
            makeEntry("123.45", .transfer, on: date(2026, 1, 5), account: checking, to: savings),
            makeEntry("0.45", .transfer, on: date(2026, 1, 6), account: savings, to: checking)
        ]
        let a = BalanceCalculator.balance(accountID: checking, openingBalance: dec("10"), entries: entries)
        let b = BalanceCalculator.balance(accountID: savings, openingBalance: dec("5"), entries: entries)
        XCTAssertEqual(a + b, dec("15"))
    }

    func testAsOfExcludesLaterEntriesAndIsInclusive() {
        let entries = [
            makeEntry("100", .income, on: date(2026, 1, 10), account: checking),
            makeEntry("40", .expense, on: date(2026, 1, 20), account: checking),
            makeEntry("500", .income, on: date(2026, 2, 1), account: checking)
        ]
        let opening = dec("10")
        XCTAssertEqual(BalanceCalculator.balance(accountID: checking, openingBalance: opening, entries: entries, asOf: date(2026, 1, 9)), dec("10"))
        XCTAssertEqual(BalanceCalculator.balance(accountID: checking, openingBalance: opening, entries: entries, asOf: date(2026, 1, 10)), dec("110"))
        XCTAssertEqual(BalanceCalculator.balance(accountID: checking, openingBalance: opening, entries: entries, asOf: date(2026, 1, 25)), dec("70"))
        XCTAssertEqual(BalanceCalculator.balance(accountID: checking, openingBalance: opening, entries: entries, asOf: nil), dec("570"))
    }

    func testAsOfAppliesToTransfersToo() {
        let entries = [makeEntry("300", .transfer, on: date(2026, 3, 1), account: checking, to: savings)]
        XCTAssertEqual(
            BalanceCalculator.balance(accountID: savings, openingBalance: 0, entries: entries, asOf: date(2026, 2, 28)),
            0
        )
        XCTAssertEqual(
            BalanceCalculator.balance(accountID: savings, openingBalance: 0, entries: entries, asOf: date(2026, 3, 1)),
            dec("300")
        )
    }

    func testNegativeBalanceIsPossible() {
        let entries = [makeEntry("80", .expense, on: date(2026, 1, 5), account: checking)]
        XCTAssertEqual(BalanceCalculator.balance(accountID: checking, openingBalance: dec("30"), entries: entries), dec("-50"))
    }
}
