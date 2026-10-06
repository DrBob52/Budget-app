import Foundation
import WatchConnectivity
import TallyCore

/// Receives the budget snapshot from the iPhone and queues expenses logged on the watch.
final class WatchSessionModel: NSObject, WCSessionDelegate, ObservableObject {
    private static let cacheKey = "watch.cachedSnapshot"

    @Published private(set) var snapshot: BudgetSnapshot
    /// False while showing the built-in sample because nothing has arrived yet.
    @Published private(set) var hasRealData: Bool

    override init() {
        let cached = UserDefaults.standard.data(forKey: WatchSessionModel.cacheKey)
            .flatMap { SnapshotStore.decode($0) }
        self.snapshot = cached ?? BudgetSnapshot.placeholder
        self.hasRealData = cached != nil
        super.init()
        activate()
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Queues an expense for the phone. `transferUserInfo` survives disconnects.
    func logExpense(amount: Decimal, categoryID: UUID?, title: String) {
        var payload: [String: Any] = [
            "id": UUID().uuidString,
            "amount": "\(amount)",
            "title": title,
            "date": Date().timeIntervalSince1970
        ]
        if let categoryID {
            payload["categoryID"] = categoryID.uuidString
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["logExpense": payload])
    }

    // MARK: - Snapshot handling

    private func apply(context: [String: Any]) {
        guard let data = context["snapshot"] as? Data,
              let decoded = SnapshotStore.decode(data) else { return }
        UserDefaults.standard.set(data, forKey: WatchSessionModel.cacheKey)
        DispatchQueue.main.async {
            self.snapshot = decoded
            self.hasRealData = true
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            apply(context: session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(context: applicationContext)
    }
}
