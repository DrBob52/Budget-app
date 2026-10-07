import Foundation
import Observation
import StoreKit

/// Tally Pro subscription state, backed by StoreKit 2.
///
/// `RootView` calls `start()` once at launch. After that `isPro` follows the user's
/// entitlements, including renewals, refunds and purchases made on another device.
///
/// StoreKit's own transaction type is always written `StoreKit.Transaction`, because the
/// app has a SwiftData model with the same name.
@Observable
final class ProStore {
    static let monthlyProductID = "com.tallybudget.pro.monthly"
    static let yearlyProductID = "com.tallybudget.pro.yearly"
    /// Display order: yearly first.
    static let productIDs: [String] = [yearlyProductID, monthlyProductID]

    private(set) var isPro: Bool = false
    /// Loaded subscription products, yearly first. Empty until `start()` finishes or when the
    /// store is unreachable.
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts: Bool = false
    private(set) var isPurchasing: Bool = false
    /// Last problem worth showing to the user. The paywall clears it when it retries.
    var errorMessage: String?

    #if DEBUG
    /// Developer switch that unlocks every feature without a purchase.
    var debugUnlockAll: Bool = false {
        didSet { UserDefaults.standard.set(debugUnlockAll, forKey: "tally.debugUnlockAll") }
    }
    #endif

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted: Bool = false

    init() {
        #if DEBUG
        debugUnlockAll = UserDefaults.standard.bool(forKey: "tally.debugUnlockAll")
        #endif
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: Gating

    func isUnlocked(_ feature: ProFeature) -> Bool {
        #if DEBUG
        if debugUnlockAll { return true }
        #endif
        if !feature.requiresPro { return true }
        return isPro
    }

    // MARK: Lifecycle

    /// Loads products, checks current entitlements and starts listening for transaction updates.
    @MainActor
    func start() async {
        if !hasStarted {
            hasStarted = true
            listenForTransactions()
        }
        await refreshEntitlements()
        await loadProducts()
    }

    /// Fetches the subscription products. Safe to call again to retry after a failure.
    @MainActor
    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched: [Product] = try await Product.products(for: Self.productIDs)
            products = fetched.sorted { lhs, rhs in
                let left: Int = Self.productIDs.firstIndex(of: lhs.id) ?? Int.max
                let right: Int = Self.productIDs.firstIndex(of: rhs.id) ?? Int.max
                return left < right
            }
        } catch {
            products = []
        }
    }

    // MARK: Purchasing

    @MainActor
    func purchase(_ product: Product) async throws {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        let result: Product.PurchaseResult = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction: StoreKit.Transaction = try Self.verified(verification)
            await transaction.finish()
            await refreshEntitlements()
        case .pending:
            errorMessage = String(localized: "Your purchase is waiting for approval. Pro unlocks as soon as it goes through.")
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    /// Re-syncs with the App Store and re-checks entitlements.
    @MainActor
    func restore() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro {
                errorMessage = String(localized: "No active Tally Pro subscription was found for this Apple ID.")
            }
        } catch {
            errorMessage = String(localized: "Could not restore purchases. \(error.localizedDescription)")
        }
    }

    // MARK: Entitlements

    @MainActor
    private func refreshEntitlements() async {
        var active = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.productIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate != nil { continue }
            if let expiration = transaction.expirationDate, expiration <= Date() { continue }
            active = true
        }
        isPro = active
    }

    private func listenForTransactions() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let store = self else { return }
                await store.handle(update: result)
            }
        }
    }

    @MainActor
    private func handle(update result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw ProStoreError.failedVerification
        }
    }
}

fileprivate enum ProStoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return String(localized: "The App Store could not verify this purchase.")
        }
    }
}

enum ProFeature: String, CaseIterable, Identifiable {
    case sharedBudgets
    case unlimitedGoals
    case advancedInsights
    case recurring
    case widgetsAndWatch

    var id: String { rawValue }

    /// Recurring transactions, widgets and the Watch app are part of the free tier.
    var requiresPro: Bool {
        switch self {
        case .recurring, .widgetsAndWatch: return false
        case .sharedBudgets, .unlimitedGoals, .advancedInsights: return true
        }
    }

    var title: String {
        switch self {
        case .sharedBudgets: return String(localized: "Shared budgets")
        case .unlimitedGoals: return String(localized: "Unlimited goals")
        case .advancedInsights: return String(localized: "Advanced insights")
        case .recurring: return String(localized: "Recurring transactions")
        case .widgetsAndWatch: return String(localized: "Widgets and Apple Watch")
        }
    }

    var symbol: String {
        switch self {
        case .sharedBudgets: return "person.2"
        case .unlimitedGoals: return "flag"
        case .advancedInsights: return "chart.line.uptrend.xyaxis"
        case .recurring: return "repeat"
        case .widgetsAndWatch: return "applewatch"
        }
    }

    var blurb: String {
        switch self {
        case .sharedBudgets: return String(localized: "Split costs with the people you live with and settle up in a tap.")
        case .unlimitedGoals: return String(localized: "Save toward as many goals as you like, each with its own pace.")
        case .advancedInsights: return String(localized: "Trends, comparisons and patterns across every period.")
        case .recurring: return String(localized: "Bills and subscriptions that log themselves.")
        case .widgetsAndWatch: return String(localized: "Your budget on the Home Screen, Lock Screen and wrist.")
        }
    }
}
