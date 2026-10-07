import AppIntents
import Foundation
import SwiftData
import TallyCore

struct CheckBudgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Check my budget"
    static var description = IntentDescription("Hear how much is left to spend this period.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings.shared
        let context = IntentDataStack.context
        let now = Date()
        let snapshot = SnapshotService.makeSnapshot(context: context, settings: settings, now: now)
            ?? SnapshotStore.sharedDirectory.flatMap { SnapshotStore.read(from: $0) }

        guard let snapshot else {
            return .result(dialog: "I could not read your budget just now. Open Tally and try again.")
        }

        let message = describe(snapshot, settings: settings)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }

    private func describe(_ snapshot: BudgetSnapshot, settings: AppSettings) -> String {
        func money(_ value: Decimal) -> String {
            MoneyFormat.string(value, currencyCode: snapshot.currencyCode)
        }

        if snapshot.totalBudget <= 0 {
            return String(localized: "You have not set any category budgets for \(snapshot.periodTitle) yet. You have spent \(money(snapshot.spent)).")
        }
        if snapshot.leftToSpend < 0 {
            return String(localized: "You are \(money(-snapshot.leftToSpend)) over budget for \(snapshot.periodTitle).")
        }
        let days = snapshot.daysRemaining
        if let allowance = snapshot.dailyAllowance, days > 0 {
            return String(localized: "You have \(money(snapshot.leftToSpend)) left to spend. That is about \(money(allowance)) a day for the next ^[\(days) day](inflect: true).")
        }
        return String(localized: "You have \(money(snapshot.leftToSpend)) left to spend for \(snapshot.periodTitle).")
    }
}
