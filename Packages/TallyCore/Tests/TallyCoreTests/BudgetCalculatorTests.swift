import XCTest
@testable import TallyCore

final class BudgetSummaryTests: XCTestCase {
    private let groceries = uuid(1)
    private let dining = uuid(2)
    private let transport = uuid(3)
    private let other = uuid(4)

    private var calc: PeriodCalculator { monthlyCalculator() }
    private var october: BudgetPeriod { calc.period(containing: date(2026, 10, 15)) }

    private func summarize(
        _ period: BudgetPeriod,
        entries: [LedgerEntry],
        budgets: [CategoryBudget],
        rollover: Bool = false,
        lookback: Int = 12,
        now: Date = date(2026, 10, 22)
    ) -> PeriodSummary {
        BudgetCalculator.summary(
            for: period,
            entries: entries,
            budgets: budgets,
            calculator: calc,
            rolloverEnabled: rollover,
            rolloverLookback: lookback,
            now: now
        )
    }

    private func carried(_ summary: PeriodSummary, _ id: UUID) -> Decimal? {
        summary.status(for: id)?.carriedOver
    }

    // MARK: Totals

    private var octoberEntries: [LedgerEntry] {
        [
            makeEntry("3000", .income, on: date(2026, 10, 1)),
            makeEntry("200.50", on: date(2026, 10, 3), category: groceries),
            makeEntry("99.50", on: date(2026, 10, 10), category: groceries),
            makeEntry("80", on: date(2026, 10, 4), category: dining),
            makeEntry("40", on: date(2026, 10, 5), category: nil),
            makeEntry("25", on: date(2026, 10, 6), category: transport),
            makeEntry("500", .transfer, on: date(2026, 10, 7), account: uuid(10), to: uuid(11)),
            // Outside the period on both sides (end is exclusive).
            makeEntry("999", on: date(2026, 11, 1), category: groceries),
            makeEntry("10", on: date(2026, 9, 30), category: groceries)
        ]
    }

    private var budgets: [CategoryBudget] {
        [
            CategoryBudget(id: groceries, name: "Groceries", limit: dec("400")),
            CategoryBudget(id: dining, name: "Dining", limit: dec("100")),
            CategoryBudget(id: transport, name: "Transport", limit: 0) // zero limit = no budget
        ]
    }

    func testTotals_incomeExpensesAndTransfersIgnored() {
        let s = summarize(october, entries: octoberEntries, budgets: budgets)
        XCTAssertEqual(s.income, dec("3000"))
        XCTAssertEqual(s.expenses, dec("445"))
        XCTAssertEqual(s.net, dec("2555"))
    }

    func testBudgetedVersusUnbudgetedSpending() {
        let s = summarize(october, entries: octoberEntries, budgets: budgets)
        XCTAssertEqual(s.totalBudget, dec("500"))
        XCTAssertEqual(s.budgetedSpent, dec("380"))
        // 40 uncategorized + 25 in a category whose limit is zero.
        XCTAssertEqual(s.unbudgetedSpent, dec("65"))
        XCTAssertEqual(s.budgetedSpent + s.unbudgetedSpent, s.expenses)
    }

    func testLeftToSpendSubtractsAllExpenses_includingUnbudgeted() {
        let s = summarize(october, entries: octoberEntries, budgets: budgets)
        XCTAssertEqual(s.leftToSpend, dec("55"))
    }

    func testSpentByCategoryKeysIncludeUncategorized() {
        let s = summarize(october, entries: octoberEntries, budgets: budgets)
        let none: UUID? = nil
        XCTAssertEqual(s.spentByCategory[groceries], dec("300"))
        XCTAssertEqual(s.spentByCategory[dining], dec("80"))
        XCTAssertEqual(s.spentByCategory[transport], dec("25"))
        XCTAssertEqual(s.spentByCategory[none], dec("40"))
        XCTAssertEqual(s.spentByCategory.count, 4)
    }

    func testOnlyBudgetedCategoriesGetStatuses() {
        let s = summarize(october, entries: octoberEntries, budgets: budgets)
        XCTAssertEqual(s.categoryStatuses.count, 2)
        XCTAssertNil(s.status(for: transport))
        XCTAssertNil(s.status(for: other))
        let g = s.status(for: groceries)
        XCTAssertEqual(g?.limit, dec("400"))
        XCTAssertEqual(g?.spent, dec("300"))
        XCTAssertEqual(g?.remaining, dec("100"))
        XCTAssertEqual(g?.isOver, false)
    }

    func testDailyAllowance() {
        let s = summarize(october, entries: octoberEntries, budgets: budgets, now: date(2026, 10, 22))
        XCTAssertEqual(s.daysRemaining, 10)
        XCTAssertEqual(s.dailyAllowance, dec("5.5"))
    }

    func testDailyAllowanceIsNeverNegative() {
        let entries = [makeEntry("900", on: date(2026, 10, 2), category: groceries)]
        let s = summarize(october, entries: entries, budgets: budgets)
        XCTAssertEqual(s.leftToSpend, dec("-400"))
        XCTAssertEqual(s.dailyAllowance, 0)
    }

    func testDailyAllowanceNilForPastPeriodAndWithoutBudget() {
        let past = summarize(october, entries: octoberEntries, budgets: budgets, now: date(2026, 11, 5))
        XCTAssertEqual(past.daysRemaining, 0)
        XCTAssertNil(past.dailyAllowance)

        let noBudget = summarize(october, entries: octoberEntries, budgets: [])
        XCTAssertEqual(noBudget.totalBudget, 0)
        XCTAssertNil(noBudget.dailyAllowance)
        XCTAssertEqual(noBudget.unbudgetedSpent, noBudget.expenses)
    }

    func testDaysRemainingBeforePeriodStartsIsFullLength() {
        let s = summarize(october, entries: [], budgets: budgets, now: date(2026, 9, 15))
        XCTAssertEqual(s.daysRemaining, 31)
    }

    func testEmptyEntries() {
        let s = summarize(october, entries: [], budgets: budgets)
        XCTAssertEqual(s.income, 0)
        XCTAssertEqual(s.expenses, 0)
        XCTAssertEqual(s.totalBudget, 500)
        XCTAssertEqual(s.leftToSpend, 500)
        XCTAssertTrue(s.spentByCategory.isEmpty)
    }

    func testSpendingHelper_onlyExpensesInsidePeriod() {
        let totals = BudgetCalculator.spending(in: october, entries: octoberEntries)
        XCTAssertEqual(totals[groceries], dec("300"))
        XCTAssertEqual(totals.values.reduce(Decimal(0), +), dec("445"))
    }

    // MARK: Rollover

    /// Limit 100 for groceries. Spending: Jul 60, Aug 130, Sep none.
    private var rolloverEntries: [LedgerEntry] {
        [
            makeEntry("60", on: date(2026, 7, 15), category: groceries),
            makeEntry("130", on: date(2026, 8, 10), category: groceries)
        ]
    }

    private func rollBudget(rolls: Bool = true) -> [CategoryBudget] {
        [CategoryBudget(id: groceries, name: "Groceries", limit: dec("100"), rollsOver: rolls)]
    }

    func testRolloverOff_noCarryOver() {
        let s = summarize(october, entries: rolloverEntries, budgets: rollBudget(), rollover: false)
        XCTAssertEqual(carried(s, groceries), 0)
        XCTAssertEqual(s.totalBudget, dec("100"))
    }

    func testRolloverEnabledButCategoryDoesNotRollOver_isIgnored() {
        let s = summarize(october, entries: rolloverEntries, budgets: rollBudget(rolls: false), rollover: true)
        XCTAssertEqual(carried(s, groceries), 0)
        XCTAssertEqual(s.totalBudget, dec("100"))
    }

    func testPositiveAndNegativeCarryAcrossThreePreviousPeriods() {
        // Jul: 100-60 = 40; Aug: 40+100-130 = 10; Sep: 10+100-0 = 110.
        let entries = rolloverEntries + [makeEntry("50", on: date(2026, 10, 12), category: groceries)]
        let s = summarize(october, entries: entries, budgets: rollBudget(), rollover: true)
        XCTAssertEqual(carried(s, groceries), dec("110"))
        let g = s.status(for: groceries)
        XCTAssertEqual(g?.available, dec("210"))
        XCTAssertEqual(g?.remaining, dec("160"))
        XCTAssertEqual(s.totalBudget, dec("210"))
        XCTAssertEqual(s.leftToSpend, dec("160"))
    }

    func testCarryAfterTwoPeriods_canBeNegative() {
        // Looking back 2 periods ignores July: Aug: 100-130 = -30; Sep: -30+100 = 70.
        let s2 = summarize(october, entries: rolloverEntries, budgets: rollBudget(), rollover: true, lookback: 2)
        XCTAssertEqual(carried(s2, groceries), dec("70"))

        // A single period back is just September.
        let s1 = summarize(october, entries: rolloverEntries, budgets: rollBudget(), rollover: true, lookback: 1)
        XCTAssertEqual(carried(s1, groceries), dec("100"))
    }

    func testNegativeCarryFromOverspending() {
        // Only August has entries: 100-250 = -150 for Aug, Sep adds +100 => -50.
        let entries = [makeEntry("250", on: date(2026, 8, 10), category: groceries)]
        let oct = summarize(october, entries: entries, budgets: rollBudget(), rollover: true)
        XCTAssertEqual(carried(oct, groceries), dec("-50"))
        XCTAssertEqual(oct.status(for: groceries)?.available, dec("50"))

        let sep = calc.period(containing: date(2026, 9, 10))
        let s = summarize(sep, entries: entries, budgets: rollBudget(), rollover: true)
        XCTAssertEqual(carried(s, groceries), dec("-150"))
        XCTAssertEqual(s.status(for: groceries)?.available, dec("-50"))
        XCTAssertEqual(s.totalBudget, dec("-50"))
    }

    func testNegativeAvailableNeverGivesDailyAllowance() {
        let entries = [makeEntry("250", on: date(2026, 8, 10), category: groceries)]
        let sep = calc.period(containing: date(2026, 9, 10))
        let s = summarize(sep, entries: entries, budgets: rollBudget(), rollover: true, now: date(2026, 9, 10))
        XCTAssertNil(s.dailyAllowance)
    }

    func testNoCarryBeforeTheFirstEntry() {
        // First entry is on Aug 10, so August is the earliest period that can contribute.
        let entries = [makeEntry("30", on: date(2026, 8, 10), category: groceries)]

        let aug = calc.period(containing: date(2026, 8, 20))
        let augSummary = summarize(aug, entries: entries, budgets: rollBudget(), rollover: true)
        XCTAssertEqual(carried(augSummary, groceries), 0, "the first entry's own period has nothing before it")

        let jul = calc.period(containing: date(2026, 7, 20))
        let julSummary = summarize(jul, entries: entries, budgets: rollBudget(), rollover: true)
        XCTAssertEqual(carried(julSummary, groceries), 0, "periods before the first entry get no carry")

        // September carries only August: 100 - 30.
        let sep = calc.period(containing: date(2026, 9, 20))
        let sepSummary = summarize(sep, entries: entries, budgets: rollBudget(), rollover: true)
        XCTAssertEqual(carried(sepSummary, groceries), dec("70"))
    }

    func testNoCarryWithoutAnyEntries() {
        let s = summarize(october, entries: [], budgets: rollBudget(), rollover: true)
        XCTAssertEqual(carried(s, groceries), 0)
    }

    func testRolloverLookbackZeroGivesNoCarry() {
        let s = summarize(october, entries: rolloverEntries, budgets: rollBudget(), rollover: true, lookback: 0)
        XCTAssertEqual(carried(s, groceries), 0)
    }

    func testCarryOnlyCountsTheOwnCategoryAndExpenses() {
        let entries = [
            makeEntry("60", on: date(2026, 8, 10), category: groceries),
            makeEntry("500", on: date(2026, 8, 12), category: dining),
            makeEntry("900", .income, on: date(2026, 8, 13), category: groceries),
            makeEntry("700", .transfer, on: date(2026, 8, 14), category: groceries)
        ]
        let s = summarize(october, entries: entries, budgets: rollBudget(), rollover: true)
        // Aug: 100-60 = 40, Sep: +100 = 140.
        XCTAssertEqual(carried(s, groceries), dec("140"))
    }

    func testRolloverMixedCategories() {
        let budgets = [
            CategoryBudget(id: groceries, name: "Groceries", limit: dec("100"), rollsOver: true),
            CategoryBudget(id: dining, name: "Dining", limit: dec("50"), rollsOver: false)
        ]
        let entries = [
            makeEntry("40", on: date(2026, 9, 5), category: groceries),
            makeEntry("10", on: date(2026, 9, 6), category: dining)
        ]
        let s = summarize(october, entries: entries, budgets: budgets, rollover: true)
        XCTAssertEqual(carried(s, groceries), dec("60"))
        XCTAssertEqual(carried(s, dining), 0)
        XCTAssertEqual(s.totalBudget, dec("210"))
    }

    func testRolloverWorksWithMonthlyStartDay25() {
        let calc25 = monthlyCalculator(startDay: 25)
        let period = calc25.period(containing: date(2026, 10, 30)) // Oct 25 - Nov 25
        let entries = [makeEntry("70", on: date(2026, 9, 28), category: groceries)] // Sep 25 - Oct 25
        let s = BudgetCalculator.summary(
            for: period,
            entries: entries,
            budgets: rollBudget(),
            calculator: calc25,
            rolloverEnabled: true,
            now: date(2026, 10, 30)
        )
        XCTAssertEqual(carried(s, groceries), dec("30"))
    }
}

final class CategoryStatusTests: XCTestCase {
    func testAvailableRemainingAndIsOver() {
        let s = CategoryStatus(id: uuid(1), limit: dec("100"), carriedOver: dec("50"), spent: dec("30"))
        XCTAssertEqual(s.available, dec("150"))
        XCTAssertEqual(s.remaining, dec("120"))
        XCTAssertFalse(s.isOver)
        XCTAssertEqual(s.progress, 0.2, accuracy: 1e-9)
    }

    func testOverspent() {
        let s = CategoryStatus(id: uuid(1), limit: dec("100"), carriedOver: 0, spent: dec("130"))
        XCTAssertTrue(s.isOver)
        XCTAssertEqual(s.remaining, dec("-30"))
        XCTAssertEqual(s.progress, 1.3, accuracy: 1e-9)
    }

    func testExactlySpentIsNotOver() {
        let s = CategoryStatus(id: uuid(1), limit: dec("100"), carriedOver: 0, spent: dec("100"))
        XCTAssertFalse(s.isOver)
        XCTAssertEqual(s.remaining, 0)
        XCTAssertEqual(s.progress, 1.0, accuracy: 1e-9)
    }

    func testProgressWithNothingAvailable() {
        let none = CategoryStatus(id: uuid(1), limit: dec("100"), carriedOver: dec("-100"), spent: 0)
        XCTAssertEqual(none.progress, 0)
        let overspent = CategoryStatus(id: uuid(1), limit: dec("100"), carriedOver: dec("-150"), spent: dec("5"))
        XCTAssertEqual(overspent.progress, 1)
        XCTAssertTrue(overspent.isOver)
    }

    func testTransactionKindMetadata() {
        XCTAssertEqual(TransactionKind.allCases.count, 3)
        for kind in TransactionKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertEqual(kind.id, kind.rawValue)
        }
    }
}
