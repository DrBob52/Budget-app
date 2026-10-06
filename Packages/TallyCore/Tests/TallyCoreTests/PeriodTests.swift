import XCTest
@testable import TallyCore

final class PeriodCalculatorTests: XCTestCase {
    private func calculator(
        _ kind: PeriodKind = .monthly,
        startDay: Int = 1,
        weekday: Int = 2,
        anchor: Date = date(2024, 1, 1)
    ) -> PeriodCalculator {
        PeriodCalculator(
            settings: PeriodSettings(
                kind: kind,
                monthlyStartDay: startDay,
                weeklyStartWeekday: weekday,
                biweeklyAnchor: anchor
            ),
            calendar: utcCalendar
        )
    }

    private func assertPeriod(
        _ period: BudgetPeriod,
        _ start: Date,
        _ end: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(period.start, start, "start", file: file, line: line)
        XCTAssertEqual(period.end, end, "end", file: file, line: line)
    }

    // MARK: Monthly, start day 1

    func testMonthlyStartDay1_midMonth() {
        let p = calculator().period(containing: date(2026, 10, 15))
        assertPeriod(p, date(2026, 10, 1), date(2026, 11, 1))
    }

    func testMonthlyStartDay1_firstDayIsInclusive() {
        let p = calculator().period(containing: date(2026, 10, 1))
        assertPeriod(p, date(2026, 10, 1), date(2026, 11, 1))
    }

    func testMonthlyStartDay1_lastInstantOfMonth() {
        let p = calculator().period(containing: date(2026, 10, 31, hour: 23, minute: 59, second: 59))
        assertPeriod(p, date(2026, 10, 1), date(2026, 11, 1))
    }

    func testMonthlyStartDay1_timeOfDayDoesNotMatter() {
        let calc = calculator()
        XCTAssertEqual(
            calc.period(containing: date(2026, 10, 15, hour: 0)),
            calc.period(containing: date(2026, 10, 15, hour: 17, minute: 30))
        )
    }

    func testMonthlyStartDay1_yearBoundary() {
        let calc = calculator()
        assertPeriod(calc.period(containing: date(2025, 12, 31)), date(2025, 12, 1), date(2026, 1, 1))
        assertPeriod(calc.period(containing: date(2026, 1, 1)), date(2026, 1, 1), date(2026, 2, 1))
    }

    func testMonthlyStartDay1_leapFebruary() {
        let p = calculator().period(containing: date(2024, 2, 29))
        assertPeriod(p, date(2024, 2, 1), date(2024, 3, 1))
        XCTAssertEqual(p.dayCount(calendar: utcCalendar), 29)
        let nonLeap = calculator().period(containing: date(2025, 2, 10))
        XCTAssertEqual(nonLeap.dayCount(calendar: utcCalendar), 28)
    }

    // MARK: Monthly, start day 25

    func testMonthlyStartDay25_dateBeforeStartDayBelongsToPreviousMonthsPeriod() {
        let p = calculator(startDay: 25).period(containing: date(2026, 10, 10))
        assertPeriod(p, date(2026, 9, 25), date(2026, 10, 25))
    }

    func testMonthlyStartDay25_dayBeforeStartDay() {
        let p = calculator(startDay: 25).period(containing: date(2026, 10, 24))
        assertPeriod(p, date(2026, 9, 25), date(2026, 10, 25))
    }

    func testMonthlyStartDay25_onStartDay() {
        let p = calculator(startDay: 25).period(containing: date(2026, 10, 25))
        assertPeriod(p, date(2026, 10, 25), date(2026, 11, 25))
    }

    func testMonthlyStartDay25_afterStartDay() {
        let p = calculator(startDay: 25).period(containing: date(2026, 10, 30))
        assertPeriod(p, date(2026, 10, 25), date(2026, 11, 25))
    }

    func testMonthlyStartDay25_decemberToJanuaryBoundary() {
        let calc = calculator(startDay: 25)
        // Early January belongs to the period that began in December.
        assertPeriod(calc.period(containing: date(2026, 1, 10)), date(2025, 12, 25), date(2026, 1, 25))
        // Late December starts the same period.
        assertPeriod(calc.period(containing: date(2025, 12, 30)), date(2025, 12, 25), date(2026, 1, 25))
        // The 25th of January starts the next one.
        assertPeriod(calc.period(containing: date(2026, 1, 25)), date(2026, 1, 25), date(2026, 2, 25))
    }

    func testMonthlyStartDay25_dayCounts() {
        let calc = calculator(startDay: 25)
        XCTAssertEqual(calc.period(containing: date(2025, 12, 30)).dayCount(calendar: utcCalendar), 31)
        XCTAssertEqual(calc.period(containing: date(2026, 2, 26)).dayCount(calendar: utcCalendar), 28)
    }

    func testMonthlyStartDayIsClampedTo28BySettings() {
        let settings = PeriodSettings(kind: .monthly, monthlyStartDay: 31)
        XCTAssertEqual(settings.monthlyStartDay, 28)
        let calc = PeriodCalculator(settings: settings, calendar: utcCalendar)
        assertPeriod(calc.period(containing: date(2026, 2, 28)), date(2026, 2, 28), date(2026, 3, 28))
        assertPeriod(calc.period(containing: date(2026, 3, 1)), date(2026, 2, 28), date(2026, 3, 28))
    }

    // MARK: Weekly

    func testWeeklyMondayStart_midWeek() {
        // 2024-01-01 is a Monday.
        let p = calculator(.weekly, weekday: 2).period(containing: date(2024, 1, 3))
        assertPeriod(p, date(2024, 1, 1), date(2024, 1, 8))
    }

    func testWeeklyMondayStart_mondayItself() {
        let p = calculator(.weekly, weekday: 2).period(containing: date(2024, 1, 8))
        assertPeriod(p, date(2024, 1, 8), date(2024, 1, 15))
    }

    func testWeeklyMondayStart_sundayBelongsToWeekThatStartedSixDaysEarlier() {
        let p = calculator(.weekly, weekday: 2).period(containing: date(2024, 1, 7, hour: 22))
        assertPeriod(p, date(2024, 1, 1), date(2024, 1, 8))
    }

    func testWeeklyMondayStart_crossesYearBoundary() {
        // Wed 2025-12-31 -> Monday 2025-12-29.
        let p = calculator(.weekly, weekday: 2).period(containing: date(2025, 12, 31))
        assertPeriod(p, date(2025, 12, 29), date(2026, 1, 5))
    }

    func testWeeklySundayStart() {
        let p = calculator(.weekly, weekday: 1).period(containing: date(2024, 1, 3))
        assertPeriod(p, date(2023, 12, 31), date(2024, 1, 7))
    }

    func testWeeklySaturdayStart() {
        let p = calculator(.weekly, weekday: 7).period(containing: date(2024, 1, 3))
        assertPeriod(p, date(2023, 12, 30), date(2024, 1, 6))
    }

    func testWeeklyPeriodsAreSevenDays() {
        let p = calculator(.weekly).period(containing: date(2026, 10, 15))
        XCTAssertEqual(p.dayCount(calendar: utcCalendar), 7)
    }

    // MARK: Biweekly

    func testBiweekly_dateAfterAnchor() {
        let p = calculator(.biweekly).period(containing: date(2024, 1, 20))
        assertPeriod(p, date(2024, 1, 15), date(2024, 1, 29))
    }

    func testBiweekly_anchorItself() {
        let p = calculator(.biweekly).period(containing: date(2024, 1, 1))
        assertPeriod(p, date(2024, 1, 1), date(2024, 1, 15))
    }

    func testBiweekly_lastDayOfFirstPeriod() {
        let p = calculator(.biweekly).period(containing: date(2024, 1, 14))
        assertPeriod(p, date(2024, 1, 1), date(2024, 1, 15))
    }

    func testBiweekly_dateBeforeAnchor() {
        let calc = calculator(.biweekly)
        assertPeriod(calc.period(containing: date(2023, 12, 31)), date(2023, 12, 18), date(2024, 1, 1))
        assertPeriod(calc.period(containing: date(2023, 12, 25)), date(2023, 12, 18), date(2024, 1, 1))
        // Exactly 14 days before the anchor starts a period.
        assertPeriod(calc.period(containing: date(2023, 12, 18)), date(2023, 12, 18), date(2024, 1, 1))
        // One day further back falls in the period before that.
        assertPeriod(calc.period(containing: date(2023, 12, 17)), date(2023, 12, 4), date(2023, 12, 18))
    }

    func testBiweekly_anchorMidWeekAndFutureAnchor() {
        let calc = calculator(.biweekly, anchor: date(2024, 1, 10))
        assertPeriod(calc.period(containing: date(2024, 1, 20)), date(2024, 1, 10), date(2024, 1, 24))
        assertPeriod(calc.period(containing: date(2024, 1, 9)), date(2023, 12, 27), date(2024, 1, 10))
    }

    func testBiweekly_anchorTimeOfDayIsIgnored() {
        let calc = calculator(.biweekly, anchor: date(2024, 1, 1, hour: 15, minute: 45))
        assertPeriod(calc.period(containing: date(2024, 1, 20)), date(2024, 1, 15), date(2024, 1, 29))
        assertPeriod(calc.period(containing: date(2024, 1, 1, hour: 1)), date(2024, 1, 1), date(2024, 1, 15))
    }

    // MARK: before / after / offset

    func testPeriodAfterAndBeforeAreContiguous_forEveryKind() {
        let calcs = [
            calculator(.monthly),
            calculator(.monthly, startDay: 25),
            calculator(.weekly),
            calculator(.biweekly)
        ]
        for calc in calcs {
            let current = calc.period(containing: date(2026, 10, 15))
            let next = calc.period(after: current)
            let previous = calc.period(before: current)
            XCTAssertEqual(next.start, current.end, "\(calc.settings.kind)")
            XCTAssertEqual(previous.end, current.start, "\(calc.settings.kind)")
            XCTAssertGreaterThan(next.end, next.start)
            XCTAssertLessThan(previous.start, previous.end)
            XCTAssertEqual(calc.period(before: next), current)
            XCTAssertEqual(calc.period(after: previous), current)
        }
    }

    func testMonthlyPeriodAfterAndBefore() {
        let calc = calculator()
        let oct = calc.period(containing: date(2026, 10, 15))
        assertPeriod(calc.period(after: oct), date(2026, 11, 1), date(2026, 12, 1))
        assertPeriod(calc.period(before: oct), date(2026, 9, 1), date(2026, 10, 1))
    }

    func testPeriodBeforeAcrossYearBoundary() {
        let calc = calculator()
        let jan = calc.period(containing: date(2026, 1, 15))
        assertPeriod(calc.period(before: jan), date(2025, 12, 1), date(2026, 1, 1))
        let december = calc.period(containing: date(2025, 12, 15))
        assertPeriod(calc.period(after: december), date(2026, 1, 1), date(2026, 2, 1))
    }

    func testMonthly25PeriodAfterAndBeforeAcrossYear() {
        let calc = calculator(startDay: 25)
        let current = calc.period(containing: date(2025, 12, 30))
        assertPeriod(calc.period(after: current), date(2026, 1, 25), date(2026, 2, 25))
        assertPeriod(calc.period(before: current), date(2025, 11, 25), date(2025, 12, 25))
    }

    func testPeriodOffset_zeroReturnsSamePeriod() {
        let calc = calculator()
        let p = calc.period(containing: date(2026, 10, 15))
        XCTAssertEqual(calc.period(offset: 0, from: p), p)
    }

    func testPeriodOffset_positiveAndNegative() {
        let calc = calculator()
        let oct = calc.period(containing: date(2026, 10, 15))
        assertPeriod(calc.period(offset: 3, from: oct), date(2027, 1, 1), date(2027, 2, 1))
        assertPeriod(calc.period(offset: -10, from: oct), date(2025, 12, 1), date(2026, 1, 1))
        assertPeriod(calc.period(offset: -1, from: oct), date(2026, 9, 1), date(2026, 10, 1))
    }

    func testPeriodOffset_weekly() {
        let calc = calculator(.weekly)
        let week = calc.period(containing: date(2024, 1, 3))
        assertPeriod(calc.period(offset: 2, from: week), date(2024, 1, 15), date(2024, 1, 22))
        assertPeriod(calc.period(offset: -2, from: week), date(2023, 12, 18), date(2023, 12, 25))
    }

    // MARK: periods(endingWith:count:)

    func testPeriodsEndingWith_orderIsOldestFirstAndEndsWithLast() {
        let calc = calculator()
        let last = calc.period(containing: date(2026, 10, 15))
        let list = calc.periods(endingWith: last, count: 4)
        XCTAssertEqual(list.count, 4)
        XCTAssertEqual(list.last, last)
        XCTAssertEqual(list.map(\.start), [date(2026, 7, 1), date(2026, 8, 1), date(2026, 9, 1), date(2026, 10, 1)])
    }

    func testPeriodsEndingWith_areContiguous_forEveryKind() {
        let calcs = [
            calculator(.monthly),
            calculator(.monthly, startDay: 25),
            calculator(.weekly),
            calculator(.biweekly)
        ]
        for calc in calcs {
            let last = calc.period(containing: date(2026, 2, 10))
            let list = calc.periods(endingWith: last, count: 9)
            XCTAssertEqual(list.count, 9)
            for index in 1..<list.count {
                XCTAssertEqual(list[index - 1].end, list[index].start, "\(calc.settings.kind) index \(index)")
            }
        }
    }

    func testPeriodsEndingWith_acrossYearBoundary() {
        let calc = calculator()
        let last = calc.period(containing: date(2026, 1, 20))
        let starts = calc.periods(endingWith: last, count: 3).map(\.start)
        XCTAssertEqual(starts, [date(2025, 11, 1), date(2025, 12, 1), date(2026, 1, 1)])
    }

    func testPeriodsEndingWith_countOneZeroAndNegative() {
        let calc = calculator()
        let last = calc.period(containing: date(2026, 10, 15))
        XCTAssertEqual(calc.periods(endingWith: last, count: 1), [last])
        XCTAssertEqual(calc.periods(endingWith: last, count: 0), [])
        XCTAssertEqual(calc.periods(endingWith: last, count: -3), [])
    }

    // MARK: Invariants over a long run of days

    func testPeriodContainingAlwaysContainsTheDate_andNeighboursAreAdjacent() {
        let calcs = [
            calculator(.monthly),
            calculator(.monthly, startDay: 25),
            calculator(.monthly, startDay: 28),
            calculator(.weekly),
            calculator(.weekly, weekday: 7),
            calculator(.biweekly),
            calculator(.biweekly, anchor: date(2025, 6, 18))
        ]
        for calc in calcs {
            var day = date(2025, 12, 1)
            var previous = calc.period(containing: day.addingTimeInterval(-86_400))
            for _ in 0..<420 {
                let p = calc.period(containing: day)
                XCTAssertTrue(p.contains(day), "\(calc.settings.kind) \(day)")
                XCTAssertTrue(p.contains(day.addingTimeInterval(23 * 3600)), "\(calc.settings.kind) \(day)")
                if p != previous {
                    XCTAssertEqual(p.start, previous.end, "\(calc.settings.kind) \(day)")
                    XCTAssertEqual(p.start, day, "a new period must begin exactly at midnight of its first day")
                }
                previous = p
                day = utcCalendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
    }
}

final class BudgetPeriodTests: XCTestCase {
    private let october = BudgetPeriod(start: date(2026, 10, 1), end: date(2026, 11, 1))

    func testContains_startInclusiveEndExclusive() {
        XCTAssertTrue(october.contains(date(2026, 10, 1)))
        XCTAssertTrue(october.contains(date(2026, 10, 31, hour: 23, minute: 59, second: 59)))
        XCTAssertFalse(october.contains(date(2026, 11, 1)))
        XCTAssertFalse(october.contains(date(2026, 9, 30, hour: 23, minute: 59, second: 59)))
    }

    func testContains_oneSecondEitherSideOfTheEnd() {
        XCTAssertTrue(october.contains(october.end.addingTimeInterval(-1)))
        XCTAssertFalse(october.contains(october.end))
        XCTAssertFalse(october.contains(october.start.addingTimeInterval(-1)))
    }

    func testIdAndInterval() {
        XCTAssertEqual(october.id, october.start)
        XCTAssertEqual(october.interval.start, october.start)
        XCTAssertEqual(october.interval.end, october.end)
    }

    func testIsCurrent() {
        XCTAssertTrue(october.isCurrent(now: date(2026, 10, 20)))
        XCTAssertFalse(october.isCurrent(now: date(2026, 11, 1)))
        XCTAssertFalse(october.isCurrent(now: date(2026, 9, 1)))
    }

    func testLastDay() {
        XCTAssertEqual(october.lastDay(calendar: utcCalendar), date(2026, 10, 31))
        let week = BudgetPeriod(start: date(2024, 1, 1), end: date(2024, 1, 8))
        XCTAssertEqual(week.lastDay(calendar: utcCalendar), date(2024, 1, 7))
    }

    func testDayCount() {
        XCTAssertEqual(october.dayCount(calendar: utcCalendar), 31)
        XCTAssertEqual(BudgetPeriod(start: date(2024, 2, 1), end: date(2024, 3, 1)).dayCount(calendar: utcCalendar), 29)
        XCTAssertEqual(BudgetPeriod(start: date(2024, 1, 1), end: date(2024, 1, 8)).dayCount(calendar: utcCalendar), 7)
        XCTAssertEqual(BudgetPeriod(start: date(2024, 1, 1), end: date(2024, 1, 15)).dayCount(calendar: utcCalendar), 14)
    }

    func testDayCount_neverBelowOne() {
        let empty = BudgetPeriod(start: date(2024, 1, 1), end: date(2024, 1, 1))
        XCTAssertEqual(empty.dayCount(calendar: utcCalendar), 1)
    }

    func testDaysRemaining_countsTodayInclusive() {
        XCTAssertEqual(october.daysRemaining(from: date(2026, 10, 1), calendar: utcCalendar), 31)
        XCTAssertEqual(october.daysRemaining(from: date(2026, 10, 22), calendar: utcCalendar), 10)
        XCTAssertEqual(october.daysRemaining(from: date(2026, 10, 22, hour: 14, minute: 30), calendar: utcCalendar), 10)
        XCTAssertEqual(october.daysRemaining(from: date(2026, 10, 31, hour: 12), calendar: utcCalendar), 1)
    }

    func testDaysRemaining_zeroWhenPeriodIsOver() {
        XCTAssertEqual(october.daysRemaining(from: date(2026, 11, 1), calendar: utcCalendar), 0)
        XCTAssertEqual(october.daysRemaining(from: date(2027, 3, 1), calendar: utcCalendar), 0)
    }

    func testDaysRemaining_fullCountWhenNotStarted() {
        XCTAssertEqual(october.daysRemaining(from: date(2026, 9, 20), calendar: utcCalendar), 31)
        XCTAssertEqual(october.daysRemaining(from: date(2026, 9, 30, hour: 23, minute: 59), calendar: utcCalendar), 31)
    }

    func testTitle_isNeverEmpty() {
        let calc = monthlyCalculator()
        let month = calc.period(containing: date(2026, 10, 15))
        XCTAssertFalse(month.title(calendar: utcCalendar).isEmpty)

        let custom = monthlyCalculator(startDay: 25).period(containing: date(2026, 10, 30))
        let title = custom.title(calendar: utcCalendar)
        XCTAssertFalse(title.isEmpty)
        XCTAssertTrue(title.contains("–"), "custom ranges are rendered as 'first – last'")
        XCTAssertTrue(title.contains(where: \.isNumber))
    }

    func testCodableRoundTripAndHashable() throws {
        let data = try JSONEncoder().encode(october)
        let decoded = try JSONDecoder().decode(BudgetPeriod.self, from: data)
        XCTAssertEqual(decoded, october)
        XCTAssertEqual(Set([october, decoded]).count, 1)
    }
}

final class PeriodSettingsTests: XCTestCase {
    func testDefaults() {
        let settings = PeriodSettings()
        XCTAssertEqual(settings.kind, .monthly)
        XCTAssertEqual(settings.monthlyStartDay, 1)
        XCTAssertEqual(settings.weeklyStartWeekday, 2)
        XCTAssertEqual(settings.biweeklyAnchor, date(2024, 1, 1))
    }

    func testClamping() {
        XCTAssertEqual(PeriodSettings(monthlyStartDay: 0).monthlyStartDay, 1)
        XCTAssertEqual(PeriodSettings(monthlyStartDay: -5).monthlyStartDay, 1)
        XCTAssertEqual(PeriodSettings(monthlyStartDay: 29).monthlyStartDay, 28)
        XCTAssertEqual(PeriodSettings(weeklyStartWeekday: 0).weeklyStartWeekday, 1)
        XCTAssertEqual(PeriodSettings(weeklyStartWeekday: 9).weeklyStartWeekday, 7)
        XCTAssertEqual(PeriodSettings(monthlyStartDay: 15, weeklyStartWeekday: 4).monthlyStartDay, 15)
        XCTAssertEqual(PeriodSettings(monthlyStartDay: 15, weeklyStartWeekday: 4).weeklyStartWeekday, 4)
    }

    func testCodableRoundTrip() throws {
        let settings = PeriodSettings(kind: .biweekly, monthlyStartDay: 20, weeklyStartWeekday: 3, biweeklyAnchor: date(2025, 5, 5))
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PeriodSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testPeriodKindMetadata() {
        XCTAssertEqual(PeriodKind.allCases.count, 3)
        for kind in PeriodKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertEqual(kind.id, kind.rawValue)
        }
        XCTAssertEqual(PeriodKind(rawValue: "weekly"), .weekly)
    }
}
