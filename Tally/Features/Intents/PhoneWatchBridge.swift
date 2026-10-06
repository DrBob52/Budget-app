import Foundation
import SwiftData
import TallyCore
import WatchConnectivity

/// An expense the watch asked the phone to record.
struct PhoneWatchExpense: Sendable {
    var id: UUID?
    var amount: Decimal
    var categoryID: UUID?
    var title: String
    var date: Date

    /// Parses the `logExpense` payload sent by the watch.
    init?(payload: [String: Any]) {
        let amountText = (payload["amount"] as? String) ?? ""
        guard let amount = Decimal(string: amountText), amount > 0 else { return nil }
        self.amount = amount
        self.id = (payload["id"] as? String).flatMap { UUID(uuidString: $0) }
        self.categoryID = (payload["categoryID"] as? String).flatMap { UUID(uuidString: $0) }
        self.title = (payload["title"] as? String) ?? ""
        if let seconds = payload["date"] as? TimeInterval {
            self.date = Date(timeIntervalSince1970: seconds)
        } else {
            self.date = Date()
        }
    }
}

/// Phone side of WatchConnectivity. Sends BudgetSnapshot updates to the watch and
/// inserts expenses the watch logs. `activate` is called once from RootView.
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()

    private var container: ModelContainer?
    private var settings: AppSettings?
    private var observer: NSObjectProtocol?

    private override init() {
        super.init()
    }

    @MainActor
    func activate(container: ModelContainer, settings: AppSettings) {
        self.container = container
        self.settings = settings
        IntentDataStack.register(container)

        guard WCSession.isSupported() else { return }

        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: .budgetSnapshotDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let snapshot = notification.object as? BudgetSnapshot else { return }
                self?.push(snapshot)
            }
        }

        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        } else {
            pushStoredSnapshot()
        }
    }

    // MARK: - Sending snapshots

    private func push(_ snapshot: BudgetSnapshot) {
        guard let data = SnapshotStore.encode(snapshot) else { return }
        push(data: data)
    }

    private func push(data: Data) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(["snapshot": data])
    }

    /// Sends the last snapshot written to the App Group, e.g. right after the session activates.
    private func pushStoredSnapshot() {
        guard let directory = SnapshotStore.sharedDirectory,
              let data = try? Data(contentsOf: SnapshotStore.url(in: directory)) else { return }
        push(data: data)
    }

    // MARK: - Receiving expenses

    @MainActor
    private func insertExpense(_ expense: PhoneWatchExpense) {
        let usingFallback = container == nil
        let resolvedContainer = container ?? IntentDataStack.container
        let resolvedSettings = settings ?? AppSettings.shared
        let context = resolvedContainer.mainContext

        // Skip a delivery that was already recorded.
        if let id = expense.id {
            let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }
        }

        let category = expense.categoryID.flatMap { IntentBudgetReader.category(withID: $0, in: context) }
        let account = IntentBudgetReader.defaultAccount(in: context, settings: resolvedSettings)

        let transaction = Transaction(
            amount: expense.amount,
            kind: .expense,
            title: expense.title,
            date: expense.date,
            category: category,
            account: account
        )
        if let id = expense.id {
            transaction.id = id
        }
        context.insert(transaction)
        try? context.save()

        // RootView refreshes the snapshot on save when the app is up; do it here otherwise.
        if usingFallback {
            SnapshotService.refresh(context: context, settings: resolvedSettings)
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.pushStoredSnapshot()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.pushStoredSnapshot()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let payload = userInfo["logExpense"] as? [String: Any],
              let expense = PhoneWatchExpense(payload: payload) else { return }
        Task { @MainActor in
            self.insertExpense(expense)
        }
    }
}
