import Foundation

public enum PeriodKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly
    case biweekly
    case monthly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .weekly: return String(localized: "Weekly", bundle: .module)
        case .biweekly: return String(localized: "Every two weeks", bundle: .module)
        case .monthly: return String(localized: "Monthly", bundle: .module)
        }
    }
}

/// How the user's budget cycle is laid out. Monthly budgets can start on payday.
public struct PeriodSettings: Codable, Equatable, Sendable {
    public var kind: PeriodKind
    /// Day of month a monthly period starts on, 1...28.
    public var monthlyStartDay: Int
    /// Weekday a weekly period starts on, 1 = Sunday ... 7 = Saturday.
    public var weeklyStartWeekday: Int
    /// Any date that begins a two-week period.
    public var biweeklyAnchor: Date

    public init(
        kind: PeriodKind = .monthly,
        monthlyStartDay: Int = 1,
        weeklyStartWeekday: Int = 2,
        biweeklyAnchor: Date = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
    ) {
        self.kind = kind
        self.monthlyStartDay = min(max(monthlyStartDay, 1), 28)
        self.weeklyStartWeekday = min(max(weeklyStartWeekday, 1), 7)
        self.biweeklyAnchor = biweeklyAnchor
    }
}

/// A half-open date range [start, end) that one budget covers.
public struct BudgetPeriod: Hashable, Codable, Identifiable, Sendable {
    public let start: Date
    public let end: Date

    public var id: Date { start }

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var interval: DateInterval { DateInterval(start: start, end: end) }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// The last calendar day inside the period.
    public func lastDay(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -1, to: end) ?? start
    }

    public func dayCount(calendar: Calendar = .current) -> Int {
        max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 1)
    }

    /// Days left including `date` itself. Zero when the period is over, the full count when it hasn't begun.
    public func daysRemaining(from date: Date, calendar: Calendar = .current) -> Int {
        if date >= end { return 0 }
        if date < start { return dayCount(calendar: calendar) }
        let today = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: today, to: end).day ?? 0, 1)
    }

    public func isCurrent(now: Date = Date()) -> Bool { contains(now) }

    /// "October 2026" for calendar months, "Oct 25 – Nov 24" otherwise.
    public func title(calendar: Calendar = .current) -> String {
        let startDay = calendar.component(.day, from: start)
        let isCalendarMonth = startDay == 1 && calendar.date(byAdding: .month, value: 1, to: start) == end
        if isCalendarMonth {
            return start.formatted(.dateTime.month(.wide).year())
        }
        let first = start.formatted(.dateTime.month(.abbreviated).day())
        let last = lastDay(calendar: calendar).formatted(.dateTime.month(.abbreviated).day())
        return "\(first) – \(last)"
    }
}

public struct PeriodCalculator: Sendable {
    public var settings: PeriodSettings
    public var calendar: Calendar

    public init(settings: PeriodSettings, calendar: Calendar = .current) {
        self.settings = settings
        self.calendar = calendar
    }

    public func period(containing date: Date) -> BudgetPeriod {
        let day = calendar.startOfDay(for: date)
        let start: Date
        switch settings.kind {
        case .monthly:
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            let dayOfMonth = comps.day ?? 1
            comps.day = settings.monthlyStartDay
            let thisMonthStart = calendar.date(from: comps) ?? day
            if dayOfMonth >= settings.monthlyStartDay {
                start = thisMonthStart
            } else {
                start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            }
        case .weekly:
            let weekday = calendar.component(.weekday, from: day)
            let back = (weekday - settings.weeklyStartWeekday + 7) % 7
            start = calendar.date(byAdding: .day, value: -back, to: day) ?? day
        case .biweekly:
            let anchor = calendar.startOfDay(for: settings.biweeklyAnchor)
            let diff = calendar.dateComponents([.day], from: anchor, to: day).day ?? 0
            let k = Int((Double(diff) / 14.0).rounded(.down))
            start = calendar.date(byAdding: .day, value: k * 14, to: anchor) ?? anchor
        }
        return BudgetPeriod(start: start, end: advance(start, by: 1))
    }

    public func period(after period: BudgetPeriod) -> BudgetPeriod {
        self.period(containing: period.end)
    }

    public func period(before period: BudgetPeriod) -> BudgetPeriod {
        let previousDay = calendar.date(byAdding: .day, value: -1, to: period.start) ?? period.start
        return self.period(containing: previousDay)
    }

    /// Moves `offset` periods away from `period` (negative = into the past).
    public func period(offset: Int, from period: BudgetPeriod) -> BudgetPeriod {
        var result = period
        if offset > 0 {
            for _ in 0..<offset { result = self.period(after: result) }
        } else if offset < 0 {
            for _ in 0..<(-offset) { result = self.period(before: result) }
        }
        return result
    }

    /// `count` consecutive periods ending with `last`, oldest first.
    public func periods(endingWith last: BudgetPeriod, count: Int) -> [BudgetPeriod] {
        guard count > 0 else { return [] }
        var result = [last]
        var current = last
        while result.count < count {
            current = period(before: current)
            result.append(current)
        }
        return result.reversed()
    }

    private func advance(_ start: Date, by count: Int) -> Date {
        switch settings.kind {
        case .monthly:
            return calendar.date(byAdding: .month, value: count, to: start) ?? start
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * count, to: start) ?? start
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14 * count, to: start) ?? start
        }
    }
}
