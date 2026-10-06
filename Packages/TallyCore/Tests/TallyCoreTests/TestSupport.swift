import XCTest
@testable import TallyCore

/// Gregorian calendar pinned to UTC so every test is independent of the machine's time zone.
let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// A UTC date. Defaults to midnight.
func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
    var components = DateComponents()
    components.year = y
    components.month = m
    components.day = d
    components.hour = hour
    components.minute = minute
    components.second = second
    return utcCalendar.date(from: components)!
}

/// Decimal from a string literal, never from a float.
func dec(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
}

/// Deterministic UUID: uuid(1) < uuid(2) < ... when compared by `uuidString`.
func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", n))!
}

/// Year/month/day of a date in the machine's current time zone (parsers use `.current`).
func localYMD(_ value: Date) -> [Int] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let c = calendar.dateComponents([.year, .month, .day], from: value)
    return [c.year ?? 0, c.month ?? 0, c.day ?? 0]
}

func monthlyCalculator(startDay: Int = 1) -> PeriodCalculator {
    PeriodCalculator(settings: PeriodSettings(kind: .monthly, monthlyStartDay: startDay), calendar: utcCalendar)
}

func makeEntry(
    _ amount: String,
    _ kind: TransactionKind = .expense,
    on day: Date,
    category: UUID? = nil,
    account: UUID? = nil,
    to: UUID? = nil,
    title: String = ""
) -> LedgerEntry {
    LedgerEntry(
        amount: dec(amount),
        kind: kind,
        date: day,
        categoryID: category,
        accountID: account,
        toAccountID: to,
        title: title
    )
}
