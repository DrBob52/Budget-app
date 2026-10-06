import Foundation
import SwiftData

// STUB: replaced by the Widgets/Watch/Intents feature.
// Contract: phone side of WatchConnectivity. Sends BudgetSnapshot updates to the watch and
// inserts expenses the watch logs. `activate` is called once from RootView.
final class PhoneWatchBridge {
    static let shared = PhoneWatchBridge()

    @MainActor
    func activate(container: ModelContainer, settings: AppSettings) {}
}
