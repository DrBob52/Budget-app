import SwiftUI
import WidgetKit
import TallyCore

struct WidgetBudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BudgetSnapshot
}

/// Reads the snapshot the app writes into the App Group and refreshes at midnight and every 2 hours.
struct WidgetBudgetProvider: TimelineProvider {
    static func loadSnapshot() -> BudgetSnapshot {
        guard let directory = SnapshotStore.sharedDirectory else { return .placeholder }
        return SnapshotStore.read(from: directory) ?? .placeholder
    }

    func placeholder(in context: Context) -> WidgetBudgetEntry {
        WidgetBudgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetBudgetEntry) -> Void) {
        let snapshot = context.isPreview ? BudgetSnapshot.placeholder : Self.loadSnapshot()
        completion(WidgetBudgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetBudgetEntry>) -> Void) {
        let now = Date()
        let entry = WidgetBudgetEntry(date: now, snapshot: Self.loadSnapshot())
        let twoHours = now.addingTimeInterval(2 * 60 * 60)
        let midnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) ?? twoHours
        let refresh = min(midnight, twoHours)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

/// Shared formatting for the budget widgets.
struct WidgetBudgetText {
    let snapshot: BudgetSnapshot

    func money(_ value: Decimal, compact: Bool = true) -> String {
        MoneyFormat.string(value, currencyCode: snapshot.currencyCode, compact: compact)
    }

    var left: String { money(snapshot.leftToSpend) }

    var isOver: Bool { snapshot.leftToSpend < 0 }

    var leftColor: Color {
        isOver ? WidgetPalette.negative : WidgetPalette.ink
    }

    var progress: Double {
        let value = snapshot.progress
        return value.isFinite ? value : 0
    }

    var daysLeft: String {
        let days = snapshot.daysRemaining
        if days <= 0 { return "Period ended" }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    /// "$54 per day" or the days left when there is no allowance.
    var allowanceLine: String {
        if let allowance = snapshot.dailyAllowance, snapshot.daysRemaining > 0 {
            return "\(money(allowance)) per day"
        }
        return daysLeft
    }
}
