import Foundation

public enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .biweekly: return "Every two weeks"
        case .monthly: return "Every month"
        case .quarterly: return "Every three months"
        case .yearly: return "Every year"
        }
    }

    fileprivate var step: (component: Calendar.Component, value: Int) {
        switch self {
        case .daily: return (.day, 1)
        case .weekly: return (.day, 7)
        case .biweekly: return (.day, 14)
        case .monthly: return (.month, 1)
        case .quarterly: return (.month, 3)
        case .yearly: return (.year, 1)
        }
    }
}

public struct RecurrenceRule: Codable, Hashable, Sendable {
    public var frequency: RecurrenceFrequency
    public var startDate: Date
    public var endDate: Date?

    /// Safety cap so a corrupt start date can't spin forever.
    public static let maxOccurrences = 5_000

    public init(frequency: RecurrenceFrequency, startDate: Date, endDate: Date? = nil) {
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
    }

    /// The n-th occurrence, computed from the start date so month-end dates don't drift
    /// (Jan 31 → Feb 28 → Mar 31).
    public func occurrence(_ n: Int, calendar: Calendar = .current) -> Date? {
        let step = frequency.step
        return calendar.date(byAdding: step.component, value: step.value * n, to: startDate)
    }

    /// Occurrences strictly after `after` (or from the start when nil) up to and including `through`.
    public func occurrences(after: Date?, through: Date, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var n = 0
        while n < Self.maxOccurrences, let date = occurrence(n, calendar: calendar) {
            if date > through { break }
            if let endDate, date > endDate { break }
            if after == nil || date > after! {
                result.append(date)
            }
            n += 1
        }
        return result
    }

    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        var n = 0
        while n < Self.maxOccurrences, let candidate = occurrence(n, calendar: calendar) {
            if let endDate, candidate > endDate { return nil }
            if candidate > date { return candidate }
            n += 1
        }
        return nil
    }
}
