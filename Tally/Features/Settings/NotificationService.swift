import Foundation
import SwiftData
import UserNotifications
import TallyCore

/// Schedules Tally's local notifications: a daily "log your spending" nudge, bill reminders
/// for recurring expenses, and heads-up alerts when a category budget is nearly used up.
/// Every request identifier starts with "tally." so it can be cleared in one sweep.
final class NotificationService {
    static let shared = NotificationService()

    private static let idPrefix = "tally."
    private static let overspendPrefix = "tally.overspend."
    private static let sentKey = "tally.sentOverspend"
    private static let maxBillReminders = 50

    /// Asks the system for permission to show alerts. Safe to call repeatedly.
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Removes everything Tally scheduled and forgets which overspend alerts were sent.
    func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(NotificationService.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        UserDefaults.standard.removeObject(forKey: NotificationService.sentKey)
    }

    /// Rebuilds the pending notifications from current settings and data.
    @MainActor
    func reschedule(context: ModelContext, settings: AppSettings) {
        let now = Date()
        var requests: [UNNotificationRequest] = []

        if settings.dailyReminderEnabled {
            requests.append(dailyRequest(minutes: settings.dailyReminderMinutes))
        }

        if settings.billRemindersEnabled {
            requests.append(contentsOf: billRequests(context: context, settings: settings, now: now))
        }

        var newOverspendKeys: [String] = []
        var periodStamp = ""
        if settings.overspendAlertsEnabled {
            let result = overspendRequests(context: context, settings: settings, now: now)
            requests.append(contentsOf: result.requests)
            newOverspendKeys = result.keys
            periodStamp = result.periodStamp
        }

        let center = UNUserNotificationCenter.current()
        let keys = newOverspendKeys
        let stamp = periodStamp
        let toAdd = requests
        Task { @MainActor in
            let pending = await center.pendingNotificationRequests()
            // Keep overspend alerts that are about to fire; they are one-shot and already tracked.
            let stale = pending.map(\.identifier).filter {
                $0.hasPrefix(NotificationService.idPrefix) && !$0.hasPrefix(NotificationService.overspendPrefix)
            }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }

            if !keys.isEmpty {
                var sent = (UserDefaults.standard.stringArray(forKey: NotificationService.sentKey) ?? [])
                    .filter { $0.hasSuffix("-" + stamp) }
                sent.append(contentsOf: keys)
                UserDefaults.standard.set(sent, forKey: NotificationService.sentKey)
            }
            for request in toAdd {
                try? await center.add(request)
            }
        }
    }

    // MARK: - Daily reminder

    private func dailyRequest(minutes: Int) -> UNNotificationRequest {
        var components = DateComponents()
        components.hour = min(max(minutes / 60, 0), 23)
        components.minute = min(max(minutes % 60, 0), 59)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Anything to log today?")
        content.body = String(localized: "A quick note of today's spending keeps your plan honest.")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(identifier: NotificationService.idPrefix + "daily", content: content, trigger: trigger)
    }

    // MARK: - Bills

    @MainActor
    private func billRequests(context: ModelContext, settings: AppSettings, now: Date) -> [UNNotificationRequest] {
        let templates: [RecurringTemplate] = (try? context.fetch(FetchDescriptor<RecurringTemplate>())) ?? []
        let calendar = Calendar.current

        var due: [(template: RecurringTemplate, fireDate: Date)] = []
        for template in templates {
            guard template.isActive, template.remindBeforeDue, template.kind == .expense else { continue }
            guard let dueDate = template.nextDueDate else { continue }
            let dueDay = calendar.startOfDay(for: dueDate)
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: dueDay),
                  let fireDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore),
                  fireDate > now else { continue }
            due.append((template, fireDate))
        }
        due.sort { $0.fireDate < $1.fireDate }

        var requests: [UNNotificationRequest] = []
        for item in due.prefix(NotificationService.maxBillReminders) {
            let name = item.template.title.isEmpty ? String(localized: "A bill") : item.template.title
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(name) is due tomorrow")
            content.body = String(localized: "\(settings.format(item.template.amount)) is coming out. Make sure there is enough set aside.")
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = NotificationService.idPrefix + "bill." + item.template.id.uuidString
            requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
        return requests
    }

    // MARK: - Overspend

    @MainActor
    private func overspendRequests(
        context: ModelContext,
        settings: AppSettings,
        now: Date
    ) -> (requests: [UNNotificationRequest], keys: [String], periodStamp: String) {
        let calendar = Calendar.current
        let period = settings.periodCalculator.period(containing: now)
        let stamp = "\(period.start.timeIntervalSince1970)"

        let categories: [Category] = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        // Rollover needs earlier periods, so look a year back.
        let since = calendar.date(byAdding: .year, value: -1, to: period.start) ?? period.start
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= since })
        let transactions: [Transaction] = (try? context.fetch(descriptor)) ?? []

        let summary = BudgetService.summary(for: period, transactions: transactions, categories: categories, settings: settings, now: now)
        let names: [UUID: String] = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let alreadySent = Set(UserDefaults.standard.stringArray(forKey: NotificationService.sentKey) ?? [])

        var requests: [UNNotificationRequest] = []
        var keys: [String] = []
        for status in summary.categoryStatuses {
            guard status.available > 0, status.progress >= 0.9 else { continue }
            let key = "\(status.id.uuidString)-\(stamp)"
            if alreadySent.contains(key) { continue }
            let name = names[status.id] ?? String(localized: "A category")

            let content = UNMutableNotificationContent()
            if status.isOver {
                content.title = String(localized: "\(name) is over budget")
                content.body = String(localized: "You have spent \(settings.format(status.spent)) of \(settings.format(status.available)) this period.")
            } else {
                content.title = String(localized: "\(name) is nearly used up")
                content.body = String(localized: "\(settings.format(status.remaining)) left of \(settings.format(status.available)) this period.")
            }
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let identifier = NotificationService.overspendPrefix + status.id.uuidString
            requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            keys.append(key)
        }
        return (requests, keys, stamp)
    }
}
