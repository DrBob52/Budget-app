import XCTest
@testable import TallyCore

final class RecurrenceRuleTests: XCTestCase {
    private func rule(_ frequency: RecurrenceFrequency, start: Date, end: Date? = nil) -> RecurrenceRule {
        RecurrenceRule(frequency: frequency, startDate: start, endDate: end)
    }

    // MARK: occurrence(_:)

    func testMonthlyFromJan31_leapYear() {
        let r = rule(.monthly, start: date(2024, 1, 31))
        XCTAssertEqual(r.occurrence(0, calendar: utcCalendar), date(2024, 1, 31))
        XCTAssertEqual(r.occurrence(1, calendar: utcCalendar), date(2024, 2, 29))
        XCTAssertEqual(r.occurrence(2, calendar: utcCalendar), date(2024, 3, 31), "must not drift to the 29th")
        XCTAssertEqual(r.occurrence(3, calendar: utcCalendar), date(2024, 4, 30))
        XCTAssertEqual(r.occurrence(4, calendar: utcCalendar), date(2024, 5, 31))
    }

    func testMonthlyFromJan31_nonLeapYear() {
        let r = rule(.monthly, start: date(2025, 1, 31))
        XCTAssertEqual(r.occurrence(1, calendar: utcCalendar), date(2025, 2, 28))
        XCTAssertEqual(r.occurrence(2, calendar: utcCalendar), date(2025, 3, 31))
    }

    func testOtherFrequenciesOccurrences() {
        let start = date(2024, 1, 15)
        XCTAssertEqual(rule(.daily, start: start).occurrence(3, calendar: utcCalendar), date(2024, 1, 18))
        XCTAssertEqual(rule(.weekly, start: start).occurrence(2, calendar: utcCalendar), date(2024, 1, 29))
        XCTAssertEqual(rule(.biweekly, start: start).occurrence(2, calendar: utcCalendar), date(2024, 2, 12))
        XCTAssertEqual(rule(.quarterly, start: start).occurrence(1, calendar: utcCalendar), date(2024, 4, 15))
        XCTAssertEqual(rule(.quarterly, start: start).occurrence(3, calendar: utcCalendar), date(2024, 10, 15))
        XCTAssertEqual(rule(.yearly, start: start).occurrence(2, calendar: utcCalendar), date(2026, 1, 15))
    }

    func testYearlyFromLeapDay() {
        let r = rule(.yearly, start: date(2024, 2, 29))
        XCTAssertEqual(r.occurrence(1, calendar: utcCalendar), date(2025, 2, 28))
        XCTAssertEqual(r.occurrence(4, calendar: utcCalendar), date(2028, 2, 29))
    }

    // MARK: occurrences(after:through:)

    func testMonthlyOccurrencesFromJan31() {
        let r = rule(.monthly, start: date(2024, 1, 31))
        let all = r.occurrences(after: nil, through: date(2024, 4, 30), calendar: utcCalendar)
        XCTAssertEqual(all, [date(2024, 1, 31), date(2024, 2, 29), date(2024, 3, 31), date(2024, 4, 30)])
    }

    func testThroughIsInclusive() {
        let r = rule(.weekly, start: date(2024, 1, 1))
        let list = r.occurrences(after: nil, through: date(2024, 1, 15), calendar: utcCalendar)
        XCTAssertEqual(list, [date(2024, 1, 1), date(2024, 1, 8), date(2024, 1, 15)])
        let justBefore = r.occurrences(after: nil, through: date(2024, 1, 14, hour: 23, minute: 59), calendar: utcCalendar)
        XCTAssertEqual(justBefore, [date(2024, 1, 1), date(2024, 1, 8)])
    }

    func testWeeklyOccurrencesBetweenDates() {
        let r = rule(.weekly, start: date(2024, 1, 1))
        let list = r.occurrences(after: date(2024, 1, 8), through: date(2024, 1, 29), calendar: utcCalendar)
        XCTAssertEqual(list, [date(2024, 1, 15), date(2024, 1, 22), date(2024, 1, 29)])
    }

    func testAfterIsExclusive() {
        let r = rule(.monthly, start: date(2024, 1, 31))
        let list = r.occurrences(after: date(2024, 2, 29), through: date(2024, 4, 30), calendar: utcCalendar)
        XCTAssertEqual(list, [date(2024, 3, 31), date(2024, 4, 30)])
        // Just before an occurrence it is included.
        let inclusive = r.occurrences(after: date(2024, 2, 28, hour: 23, minute: 59), through: date(2024, 3, 31), calendar: utcCalendar)
        XCTAssertEqual(inclusive, [date(2024, 2, 29), date(2024, 3, 31)])
    }

    func testAfterLaterThanThroughGivesNothing() {
        let r = rule(.daily, start: date(2024, 1, 1))
        XCTAssertEqual(r.occurrences(after: date(2024, 1, 10), through: date(2024, 1, 10), calendar: utcCalendar), [])
        XCTAssertEqual(r.occurrences(after: date(2024, 1, 20), through: date(2024, 1, 10), calendar: utcCalendar), [])
    }

    func testThroughBeforeStartGivesNothing() {
        let r = rule(.daily, start: date(2024, 6, 1))
        XCTAssertEqual(r.occurrences(after: nil, through: date(2024, 5, 31), calendar: utcCalendar), [])
    }

    func testEndDateCutsOffOccurrences_inclusive() {
        let r = rule(.monthly, start: date(2024, 1, 15), end: date(2024, 4, 15))
        let list = r.occurrences(after: nil, through: date(2024, 12, 31), calendar: utcCalendar)
        XCTAssertEqual(list, [date(2024, 1, 15), date(2024, 2, 15), date(2024, 3, 15), date(2024, 4, 15)])
    }

    func testEndDateJustBeforeOccurrenceExcludesIt() {
        let r = rule(.monthly, start: date(2024, 1, 15), end: date(2024, 4, 14))
        let list = r.occurrences(after: nil, through: date(2024, 12, 31), calendar: utcCalendar)
        XCTAssertEqual(list, [date(2024, 1, 15), date(2024, 2, 15), date(2024, 3, 15)])
    }

    func testEndDateBeforeStartGivesNothing() {
        let r = rule(.daily, start: date(2024, 3, 1), end: date(2024, 2, 1))
        XCTAssertEqual(r.occurrences(after: nil, through: date(2024, 12, 31), calendar: utcCalendar), [])
    }

    func testOccurrencesAreCappedAtMaxOccurrences() {
        let r = rule(.daily, start: date(2000, 1, 1))
        let list = r.occurrences(after: nil, through: date(2030, 1, 1), calendar: utcCalendar)
        XCTAssertEqual(RecurrenceRule.maxOccurrences, 5_000)
        XCTAssertEqual(list.count, RecurrenceRule.maxOccurrences)
    }

    // MARK: nextOccurrence

    func testNextOccurrence_basic() {
        let r = rule(.monthly, start: date(2024, 1, 31))
        XCTAssertEqual(r.nextOccurrence(after: date(2024, 1, 31), calendar: utcCalendar), date(2024, 2, 29))
        XCTAssertEqual(r.nextOccurrence(after: date(2024, 2, 15), calendar: utcCalendar), date(2024, 2, 29))
        XCTAssertEqual(r.nextOccurrence(after: date(2024, 2, 29), calendar: utcCalendar), date(2024, 3, 31))
    }

    func testNextOccurrence_beforeStartReturnsStart() {
        let r = rule(.weekly, start: date(2024, 1, 10))
        XCTAssertEqual(r.nextOccurrence(after: date(2023, 1, 1), calendar: utcCalendar), date(2024, 1, 10))
    }

    func testNextOccurrence_isStrictlyAfter() {
        let r = rule(.daily, start: date(2024, 1, 1))
        XCTAssertEqual(r.nextOccurrence(after: date(2024, 1, 5), calendar: utcCalendar), date(2024, 1, 6))
        XCTAssertEqual(r.nextOccurrence(after: date(2024, 1, 5, hour: 1), calendar: utcCalendar), date(2024, 1, 6))
    }

    func testNextOccurrence_respectsEndDate() {
        let r = rule(.monthly, start: date(2024, 1, 15), end: date(2024, 3, 15))
        XCTAssertEqual(r.nextOccurrence(after: date(2024, 2, 15), calendar: utcCalendar), date(2024, 3, 15))
        XCTAssertNil(r.nextOccurrence(after: date(2024, 3, 15), calendar: utcCalendar))
        XCTAssertNil(r.nextOccurrence(after: date(2025, 1, 1), calendar: utcCalendar))
    }

    func testNextOccurrence_givesUpAfterMaxOccurrences() {
        let r = rule(.daily, start: date(2000, 1, 1))
        XCTAssertNil(r.nextOccurrence(after: date(2030, 1, 1), calendar: utcCalendar))
    }

    // MARK: Codable / metadata

    func testCodableRoundTrip() throws {
        let r = rule(.quarterly, start: date(2024, 1, 15), end: date(2025, 1, 15))
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        XCTAssertEqual(decoded, r)
        let open = rule(.daily, start: date(2024, 1, 1))
        let openDecoded = try JSONDecoder().decode(RecurrenceRule.self, from: JSONEncoder().encode(open))
        XCTAssertNil(openDecoded.endDate)
    }

    func testFrequencyMetadata() {
        XCTAssertEqual(RecurrenceFrequency.allCases.count, 6)
        for frequency in RecurrenceFrequency.allCases {
            XCTAssertFalse(frequency.displayName.isEmpty)
            XCTAssertEqual(frequency.id, frequency.rawValue)
        }
    }
}
