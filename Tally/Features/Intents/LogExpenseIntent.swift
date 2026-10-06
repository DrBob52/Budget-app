import AppIntents
import Foundation
import SwiftData
import TallyCore

struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log an expense"
    static var description = IntentDescription("Add an expense to your budget without opening Tally.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", requestValueDialog: "How much was it?")
    var amount: Double

    @Parameter(title: "Title")
    var expenseTitle: String?

    @Parameter(title: "Category")
    var category: IntentCategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) expense in \(\.$category)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings.shared
        guard amount.isFinite, amount > 0 else {
            return .result(dialog: "That amount needs to be more than zero.")
        }

        let context = IntentDataStack.context
        let digits = MoneyFormat.fractionDigits(for: settings.currencyCode)
        let value = (Decimal(string: String(amount)) ?? 0).rounded(scale: digits)
        guard value > 0 else {
            return .result(dialog: "That amount is too small to log.")
        }

        let chosenCategory = category.flatMap { IntentBudgetReader.category(withID: $0.id, in: context) }
        let account = IntentBudgetReader.defaultAccount(in: context, settings: settings)
        let title = (expenseTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let transaction = Transaction(
            amount: value,
            kind: .expense,
            title: title,
            date: Date(),
            category: chosenCategory,
            account: account
        )
        context.insert(transaction)
        try context.save()
        SnapshotService.refresh(context: context, settings: settings)

        let message = confirmation(for: value, category: chosenCategory, context: context, settings: settings)
        return .result(dialog: "\(message)")
    }

    @MainActor
    private func confirmation(for value: Decimal, category: Category?, context: ModelContext, settings: AppSettings) -> String {
        let logged = settings.format(value)
        guard let summary = IntentBudgetReader.summary(context: context, settings: settings) else {
            return "Logged \(logged)."
        }

        if let category, category.isBudgeted, let status = summary.status(for: category.id) {
            let remaining = status.remaining
            if remaining < 0 {
                return "Logged \(logged) for \(category.name). That puts you \(settings.format(-remaining)) over budget there."
            }
            return "Logged \(logged) for \(category.name). \(settings.format(remaining)) left in \(category.name)."
        }

        let left = summary.leftToSpend
        if summary.totalBudget <= 0 {
            return "Logged \(logged)."
        }
        if left < 0 {
            return "Logged \(logged). You are \(settings.format(-left)) over budget this period."
        }
        return "Logged \(logged). \(settings.format(left)) left to spend this period."
    }
}
