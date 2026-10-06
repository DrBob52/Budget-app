import Foundation
import SwiftData

// STUB: replaced by the Settings feature.
// Contract: (re)schedules the daily reminder and bill reminders from current settings and data.
final class NotificationService {
    static let shared = NotificationService()

    @MainActor
    func reschedule(context: ModelContext, settings: AppSettings) {}
}
