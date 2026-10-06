import Foundation
import SwiftData
import TallyCore

/// Database access for App Intents and the watch bridge.
///
/// When the app is running it registers its own container (see `PhoneWatchBridge.activate`),
/// so intents and the UI share one store. When an intent runs without the app having been
/// launched, a container is opened lazily instead.
@MainActor
enum IntentDataStack {
    private static var registered: ModelContainer?
    private static var fallback: ModelContainer?

    static func register(_ container: ModelContainer) {
        registered = container
    }

    static var container: ModelContainer {
        if let registered { return registered }
        if let fallback { return fallback }
        let created = Persistence.makeContainer()
        fallback = created
        return created
    }

    static var context: ModelContext { container.mainContext }

    /// True when no container was registered by the running app.
    static var isUsingFallback: Bool { registered == nil }
}

/// Reads the current period's numbers for intents.
@MainActor
enum IntentBudgetReader {
    static func summary(context: ModelContext, settings: AppSettings, now: Date = Date()) -> PeriodSummary? {
        let period = settings.periodCalculator.period(containing: now)
        guard let categories = try? context.fetch(FetchDescriptor<Category>()) else { return nil }
        let since = Calendar.current.date(byAdding: .year, value: -1, to: period.start) ?? period.start
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= since })
        guard let transactions = try? context.fetch(descriptor) else { return nil }
        return BudgetService.summary(
            for: period,
            transactions: transactions,
            categories: categories,
            settings: settings,
            now: now
        )
    }

    static func category(withID id: UUID, in context: ModelContext) -> Category? {
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    static func account(withID id: UUID, in context: ModelContext) -> Account? {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// The default account from settings, else the first active account.
    static func defaultAccount(in context: ModelContext, settings: AppSettings) -> Account? {
        if let id = settings.defaultAccountID, let account = account(withID: id, in: context) {
            return account
        }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        return accounts
            .filter { !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }
}
