import Foundation
import Observation

// STUB: replaced by the Paywall feature (StoreKit 2).
// Contract: `isPro`, `start()` (called once at launch from RootView), `ProFeature` gating.
@Observable
final class ProStore {
    private(set) var isPro = false

    @MainActor
    func start() async {}

    func isUnlocked(_ feature: ProFeature) -> Bool { isPro }
}

enum ProFeature: String, CaseIterable, Identifiable {
    case sharedBudgets
    case bankImport
    case unlimitedGoals
    case advancedInsights
    case recurring
    case widgetsAndWatch

    var id: String { rawValue }
}
