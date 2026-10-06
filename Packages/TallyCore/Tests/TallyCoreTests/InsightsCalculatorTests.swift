import XCTest
@testable import TallyCore

final class InsightsCalculatorTests: XCTestCase {
    private let groceries = uuid(1)
    private let dining = uuid(2)
    private var calc: PeriodCalculator { monthlyCalculator() }
    private var october: BudgetPeriod { calc.period(containing: date(2026, 10, 15)) }

    // MARK: totalsByCategory

    func testTotalsByCategory_sortedDescendingWithSharesSummingToOne() {
        let entries = [
            makeEntry("50", on: date(2026, 10, 2), category: nil),
            makeEntry("100", on: date(2026, 10, 3), category: dining),
            makeEntry("50", on: date(2026, 10, 4), category: dining),
            makeEntry("200", on: date(2026, 10, 5), category: groceries),
            makeEntry("100", on: date(2026, 10, 6), category: groceries)
        ]
        let totals = InsightsCalculator.totalsByCategory(entries: entries, in: october)
        let expectedOrder: [UUID?] = [groceries, dining, nil]
        XCTAssertEqual(totals.map(\.categoryID), expectedOrder)
        XCTAssertEqual(totals.map(\.total), [dec("300"), dec("150"), dec("50")])
        XCTAssertEqual(totals[0].share, 0.6, accuracy: 1e-9)
        XCTAssertEqual(totals[1].share, 0.3, accuracy: 1e-9)
        XCTAssertEqual(totals[2].share, 0.1, accuracy: 1e-9)
        XCTAssertEqual(totals.reduce(0.0) { $0 + $1.share }, 1.0, accuracy: 1e-9)
    }

    func testTotalsByCategory_thirdsSumToApproximatelyOne() {
        let entries = [
            makeEntry("10", on: date(2026, 10, 2), category: groceries),
            makeEntry("10.01", on: date(2026, 10, 2), category: dining),
            makeEntry("10.02", on: date(2026, 10, 2), category: nil)
        ]
        let totals = InsightsCalculator.totalsByCategory(entries: entries, in: october)
        XCTAssertEqual(totals.count, 3)
        XCTAssertEqual(totals.reduce(0.0) { $0 + $1.share }, 1.0, accuracy: 1e-9)
        XCTAssertEqual(totals.first?.total, dec("10.02"))
    }

    func testTotalsByCategory_ignoresOtherKindsAndOutOfRangeEntries() {
        let entries = [
            makeEntry("100", on: date(2026, 10, 3), category: groceries),
            makeEntry("999", .income, on: date(2026, 10, 3), category: groceries),
            makeEntry("999", .transfer, on: date(2026, 10, 3), category: groceries),
            makeEntry("999", on: date(2026, 11, 1), category: groceries),
            makeEntry("999", on: date(2026, 9, 30), category: groceries)
        ]
        let totals = InsightsCalculator.totalsByCategory(entries: entries, in: october)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].total, dec("100"))
        XCTAssertEqual(totals[0].share, 1.0, accuracy: 1e-9)
    }

    func testTotalsByCategory_incomeKind() {
        let entries = [
            makeEntry("100", on: date(2026, 10, 3), category: groceries),
            makeEntry("3000", .income, on: date(2026, 10, 3), category: dining)
        ]
        let totals = InsightsCalculator.totalsByCategory(entries: entries, in: october, kind: .income)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].categoryID, dining)
        XCTAssertEqual(totals[0].total, dec("3000"))
    }

    func testTotalsByCategory_emptyAndIds() {
        XCTAssertTrue(InsightsCalculator.totalsByCategory(entries: [], in: october).isEmpty)
        let entries = [
            makeEntry("5", on: date(2026, 10, 3), category: groceries),
            makeEntry("9", on: date(2026, 10, 3), category: nil)
        ]
        let totals = InsightsCalculator.totalsByCategory(entries: entries, in: october)
        XCTAssertEqual(totals[0].id, "uncategorized")
        XCTAssertEqual(totals[1].id, groceries.uuidString)
    }

    // MARK: periodTotals

    func testPeriodTotals() {
        let periods = calc.periods(endingWith: october, count: 3) // Aug, Sep, Oct
        let entries = [
            makeEntry("3000", .income, on: date(2026, 8, 1)),
            makeEntry("1000", on: date(2026, 8, 20)),
            makeEntry("3100", .income, on: date(2026, 9, 1)),
            makeEntry("400", on: date(2026, 9, 10)),
            makeEntry("100", on: date(2026, 9, 30)),
            makeEntry("500", .transfer, on: date(2026, 9, 12)),
            makeEntry("250", on: date(2026, 10, 5)),
            makeEntry("50", on: date(2026, 11, 1)) // outside every period
        ]
        let totals = InsightsCalculator.periodTotals(entries: entries, periods: periods)
        XCTAssertEqual(totals.count, 3)
        XCTAssertEqual(totals.map(\.period), periods)
        XCTAssertEqual(totals.map(\.income), [dec("3000"), dec("3100"), 0])
        XCTAssertEqual(totals.map(\.expenses), [dec("1000"), dec("500"), dec("250")])
        XCTAssertEqual(totals.map(\.net), [dec("2000"), dec("2600"), dec("-250")])
        XCTAssertEqual(totals[0].id, periods[0].start)
    }

    func testPeriodTotals_emptyPeriods() {
        XCTAssertTrue(InsightsCalculator.periodTotals(entries: [makeEntry("5", on: date(2026, 10, 1))], periods: []).isEmpty)
    }

    // MARK: dailySpending

    private var dailyEntries: [LedgerEntry] {
        [
            makeEntry("10", on: date(2026, 10, 1, hour: 9)),
            makeEntry("5", on: date(2026, 10, 1, hour: 18)),
            makeEntry("20", on: date(2026, 10, 3, hour: 12)),
            makeEntry("100", on: date(2026, 10, 20)),
            makeEntry("999", .income, on: date(2026, 10, 2)),
            makeEntry("999", .transfer, on: date(2026, 10, 2)),
            makeEntry("999", on: date(2026, 11, 1))
        ]
    }

    func testDailySpending_cumulativeAndCutAtNow() {
        let points = InsightsCalculator.dailySpending(
            entries: dailyEntries,
            in: october,
            now: date(2026, 10, 4, hour: 12),
            calendar: utcCalendar
        )
        XCTAssertEqual(points.count, 4, "Oct 1...4 inclusive; later days are omitted")
        XCTAssertEqual(points.map(\.date), [date(2026, 10, 1), date(2026, 10, 2), date(2026, 10, 3), date(2026, 10, 4)])
        XCTAssertEqual(points.map(\.amount), [dec("15"), 0, dec("20"), 0])
        XCTAssertEqual(points.map(\.cumulative), [dec("15"), dec("15"), dec("35"), dec("35")])
    }

    func testDailySpending_nowAtStartOfFirstDayGivesOnePoint() {
        let points = InsightsCalculator.dailySpending(entries: dailyEntries, in: october, now: date(2026, 10, 1), calendar: utcCalendar)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].cumulative, dec("15"))
    }

    func testDailySpending_pastPeriodGivesOnePointPerDay() {
        let points = InsightsCalculator.dailySpending(entries: dailyEntries, in: october, now: date(2026, 12, 25), calendar: utcCalendar)
        XCTAssertEqual(points.count, 31)
        XCTAssertEqual(points.first?.date, date(2026, 10, 1))
        XCTAssertEqual(points.last?.date, date(2026, 10, 31))
        XCTAssertEqual(points.last?.cumulative, dec("135"))
        XCTAssertEqual(points[19].amount, dec("100"))
        XCTAssertEqual(points[19].cumulative, dec("135"))
        XCTAssertEqual(points[18].cumulative, dec("35"))
    }

    func testDailySpending_lastDayOfPeriodIsIncluded() {
        let points = InsightsCalculator.dailySpending(entries: [], in: october, now: date(2026, 10, 31, hour: 23), calendar: utcCalendar)
        XCTAssertEqual(points.count, 31)
        XCTAssertEqual(points.last?.cumulative, 0)
    }

    func testDailySpending_futurePeriodIsEmpty() {
        let points = InsightsCalculator.dailySpending(entries: dailyEntries, in: october, now: date(2026, 9, 15), calendar: utcCalendar)
        XCTAssertTrue(points.isEmpty)
    }

    func testDailySpending_cumulativeIsMonotonic() {
        let points = InsightsCalculator.dailySpending(entries: dailyEntries, in: october, now: date(2026, 10, 31), calendar: utcCalendar)
        for index in 1..<points.count {
            XCTAssertGreaterThanOrEqual(points[index].cumulative, points[index - 1].cumulative)
        }
    }

    // MARK: topPayees

    func testTopPayees_caseInsensitiveGroupingKeepsFirstSeenSpelling() {
        let entries = [
            makeEntry("5", on: date(2026, 10, 2), title: "Starbucks"),
            makeEntry("4", on: date(2026, 10, 3), title: "  starbucks "),
            makeEntry("3", on: date(2026, 10, 4), title: "STARBUCKS"),
            makeEntry("20", on: date(2026, 10, 5), title: "Shell"),
            makeEntry("100", on: date(2026, 10, 6), title: "Rent"),
            makeEntry("7", on: date(2026, 10, 7), title: ""),
            makeEntry("7", on: date(2026, 10, 7), title: "   "),
            makeEntry("500", .income, on: date(2026, 10, 8), title: "Employer"),
            makeEntry("500", on: date(2026, 11, 1), title: "Rent")
        ]
        let payees = InsightsCalculator.topPayees(entries: entries, in: october, limit: 5)
        XCTAssertEqual(payees.map(\.title), ["Rent", "Shell", "Starbucks"])
        XCTAssertEqual(payees.map(\.total), [dec("100"), dec("20"), dec("12")])
        XCTAssertEqual(payees.map(\.count), [1, 1, 3])
    }

    func testTopPayees_limitApplied() {
        let entries = [
            makeEntry("30", on: date(2026, 10, 2), title: "A"),
            makeEntry("20", on: date(2026, 10, 3), title: "B"),
            makeEntry("10", on: date(2026, 10, 4), title: "C")
        ]
        let top2 = InsightsCalculator.topPayees(entries: entries, in: october, limit: 2)
        XCTAssertEqual(top2.map(\.title), ["A", "B"])
        XCTAssertEqual(InsightsCalculator.topPayees(entries: entries, in: october).count, 3)
        XCTAssertTrue(InsightsCalculator.topPayees(entries: entries, in: october, limit: 0).isEmpty)
    }

    func testTopPayees_emptyInput() {
        XCTAssertTrue(InsightsCalculator.topPayees(entries: [], in: october).isEmpty)
    }

    // MARK: savingsRate / averageExpenses

    func testSavingsRate() {
        XCTAssertEqual(InsightsCalculator.savingsRate(income: dec("1000"), expenses: dec("250"))!, 0.75, accuracy: 1e-9)
        XCTAssertEqual(InsightsCalculator.savingsRate(income: dec("1000"), expenses: dec("1500"))!, -0.5, accuracy: 1e-9)
        XCTAssertEqual(InsightsCalculator.savingsRate(income: dec("1000"), expenses: 0)!, 1.0, accuracy: 1e-9)
    }

    func testSavingsRateIsNilWithoutIncome() {
        XCTAssertNil(InsightsCalculator.savingsRate(income: 0, expenses: dec("100")))
        XCTAssertNil(InsightsCalculator.savingsRate(income: 0, expenses: 0))
        XCTAssertNil(InsightsCalculator.savingsRate(income: dec("-5"), expenses: dec("1")))
    }

    func testAverageExpenses() {
        XCTAssertEqual(InsightsCalculator.averageExpenses([]), 0)
        let periods = calc.periods(endingWith: october, count: 3)
        let entries = [
            makeEntry("100", on: date(2026, 8, 5)),
            makeEntry("200", on: date(2026, 9, 5)),
            makeEntry("301", on: date(2026, 10, 5))
        ]
        let totals = InsightsCalculator.periodTotals(entries: entries, periods: periods)
        XCTAssertEqual(InsightsCalculator.averageExpenses(totals), dec("200.33333333333333333333333333333333333333").rounded(scale: 20).isZero ? 0 : InsightsCalculator.averageExpenses(totals))
        XCTAssertEqual(InsightsCalculator.averageExpenses(totals).doubleValue, 200.3333333333, accuracy: 1e-6)
    }

    func testAverageExpenses_exact() {
        let periods = calc.periods(endingWith: october, count: 2)
        let entries = [makeEntry("100", on: date(2026, 9, 5)), makeEntry("201", on: date(2026, 10, 5))]
        let totals = InsightsCalculator.periodTotals(entries: entries, periods: periods)
        XCTAssertEqual(InsightsCalculator.averageExpenses(totals), dec("150.5"))
    }
}
