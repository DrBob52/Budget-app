import Foundation
import Observation
import TallyCore

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
}

/// User preferences, persisted in the shared App Group defaults so the widget can read them.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard) {
        self.defaults = defaults
        currencyCode = defaults.string(forKey: Keys.currencyCode) ?? CurrencyCatalog.defaultCode
        periodKind = PeriodKind(rawValue: defaults.string(forKey: Keys.periodKind) ?? "") ?? .monthly
        monthlyStartDay = defaults.object(forKey: Keys.monthlyStartDay) as? Int ?? 1
        weeklyStartWeekday = defaults.object(forKey: Keys.weeklyStartWeekday) as? Int ?? Calendar.current.firstWeekday
        biweeklyAnchor = defaults.object(forKey: Keys.biweeklyAnchor) as? Date ?? Calendar.current.startOfDay(for: Date())
        rolloverEnabled = defaults.bool(forKey: Keys.rolloverEnabled)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        appLockEnabled = defaults.bool(forKey: Keys.appLockEnabled)
        dailyReminderEnabled = defaults.bool(forKey: Keys.dailyReminderEnabled)
        dailyReminderMinutes = defaults.object(forKey: Keys.dailyReminderMinutes) as? Int ?? 20 * 60
        billRemindersEnabled = defaults.object(forKey: Keys.billRemindersEnabled) as? Bool ?? true
        overspendAlertsEnabled = defaults.object(forKey: Keys.overspendAlertsEnabled) as? Bool ?? true
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        monthlyIncome = Decimal(string: defaults.string(forKey: Keys.monthlyIncome) ?? "") ?? 0
        defaultAccountID = defaults.string(forKey: Keys.defaultAccountID).flatMap(UUID.init(uuidString:))
        hideAmounts = defaults.bool(forKey: Keys.hideAmounts)
    }

    /// ISO 4217 code for every amount in the app.
    var currencyCode: String { didSet { defaults.set(currencyCode, forKey: Keys.currencyCode) } }
    var periodKind: PeriodKind { didSet { defaults.set(periodKind.rawValue, forKey: Keys.periodKind) } }
    /// Payday: first day of each monthly budget, 1...28.
    var monthlyStartDay: Int { didSet { defaults.set(monthlyStartDay, forKey: Keys.monthlyStartDay) } }
    var weeklyStartWeekday: Int { didSet { defaults.set(weeklyStartWeekday, forKey: Keys.weeklyStartWeekday) } }
    var biweeklyAnchor: Date { didSet { defaults.set(biweeklyAnchor, forKey: Keys.biweeklyAnchor) } }
    var rolloverEnabled: Bool { didSet { defaults.set(rolloverEnabled, forKey: Keys.rolloverEnabled) } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) } }
    var appLockEnabled: Bool { didSet { defaults.set(appLockEnabled, forKey: Keys.appLockEnabled) } }
    var dailyReminderEnabled: Bool { didSet { defaults.set(dailyReminderEnabled, forKey: Keys.dailyReminderEnabled) } }
    /// Minutes after midnight for the daily "log your spending" reminder.
    var dailyReminderMinutes: Int { didSet { defaults.set(dailyReminderMinutes, forKey: Keys.dailyReminderMinutes) } }
    var billRemindersEnabled: Bool { didSet { defaults.set(billRemindersEnabled, forKey: Keys.billRemindersEnabled) } }
    var overspendAlertsEnabled: Bool { didSet { defaults.set(overspendAlertsEnabled, forKey: Keys.overspendAlertsEnabled) } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    /// Expected income per period, captured during onboarding.
    var monthlyIncome: Decimal { didSet { defaults.set("\(monthlyIncome)", forKey: Keys.monthlyIncome) } }
    var defaultAccountID: UUID? { didSet { defaults.set(defaultAccountID?.uuidString, forKey: Keys.defaultAccountID) } }
    /// Blur amounts on screen (privacy mode).
    var hideAmounts: Bool { didSet { defaults.set(hideAmounts, forKey: Keys.hideAmounts) } }

    var periodSettings: PeriodSettings {
        PeriodSettings(
            kind: periodKind,
            monthlyStartDay: monthlyStartDay,
            weeklyStartWeekday: weeklyStartWeekday,
            biweeklyAnchor: biweeklyAnchor
        )
    }

    var periodCalculator: PeriodCalculator {
        PeriodCalculator(settings: periodSettings)
    }

    var currentPeriod: BudgetPeriod {
        periodCalculator.period(containing: Date())
    }

    func format(_ amount: Decimal, showsSign: Bool = false, compact: Bool = false) -> String {
        MoneyFormat.string(amount, currencyCode: currencyCode, showsSign: showsSign, compact: compact)
    }

    /// Clears every preference (used by "Erase all data").
    func reset() {
        for key in Keys.all { defaults.removeObject(forKey: key) }
        let fresh = AppSettings(defaults: defaults)
        currencyCode = fresh.currencyCode
        periodKind = fresh.periodKind
        monthlyStartDay = fresh.monthlyStartDay
        weeklyStartWeekday = fresh.weeklyStartWeekday
        biweeklyAnchor = fresh.biweeklyAnchor
        rolloverEnabled = false
        appLockEnabled = false
        dailyReminderEnabled = false
        dailyReminderMinutes = fresh.dailyReminderMinutes
        billRemindersEnabled = true
        overspendAlertsEnabled = true
        appearance = .system
        monthlyIncome = 0
        defaultAccountID = nil
        hideAmounts = false
        hasCompletedOnboarding = false
    }

    private enum Keys {
        static let currencyCode = "currencyCode"
        static let periodKind = "periodKind"
        static let monthlyStartDay = "monthlyStartDay"
        static let weeklyStartWeekday = "weeklyStartWeekday"
        static let biweeklyAnchor = "biweeklyAnchor"
        static let rolloverEnabled = "rolloverEnabled"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let appLockEnabled = "appLockEnabled"
        static let dailyReminderEnabled = "dailyReminderEnabled"
        static let dailyReminderMinutes = "dailyReminderMinutes"
        static let billRemindersEnabled = "billRemindersEnabled"
        static let overspendAlertsEnabled = "overspendAlertsEnabled"
        static let appearance = "appearance"
        static let monthlyIncome = "monthlyIncome"
        static let defaultAccountID = "defaultAccountID"
        static let hideAmounts = "hideAmounts"

        static let all = [
            currencyCode, periodKind, monthlyStartDay, weeklyStartWeekday, biweeklyAnchor,
            rolloverEnabled, hasCompletedOnboarding, appLockEnabled, dailyReminderEnabled,
            dailyReminderMinutes, billRemindersEnabled, overspendAlertsEnabled, appearance,
            monthlyIncome, defaultAccountID, hideAmounts
        ]
    }
}
