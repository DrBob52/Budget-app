import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(AppLockController.self) private var lock
    @Environment(ProStore.self) private var store

    var body: some View {
        @Bindable var router = router
        Group {
            if settings.hasCompletedOnboarding {
                tabs
            } else {
                OnboardingView()
            }
        }
        .overlay {
            if lock.isLocked {
                LockScreenView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .addTransaction(let kind):
                TransactionEditorView(transaction: nil, initialKind: kind)
            case .settings:
                SettingsView()
            case .paywall:
                PaywallView()
            }
        }
        .onOpenURL { router.handle($0) }
        .onAppear {
            lock.lockIfNeeded(settings: settings)
            PhoneWatchBridge.shared.activate(container: context.container, settings: settings)
            refreshData()
        }
        .task {
            await store.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lockIfNeeded(settings: settings)
                SnapshotService.refresh(context: context, settings: settings)
            case .active:
                refreshData()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            SnapshotService.refresh(context: context, settings: settings)
        }
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            BudgetView()
                .tabItem { Label(AppTab.budget.title, systemImage: AppTab.budget.symbol) }
                .tag(AppTab.budget)
            TransactionsView()
                .tabItem { Label(AppTab.ledger.title, systemImage: AppTab.ledger.symbol) }
                .tag(AppTab.ledger)
            InsightsView()
                .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.symbol) }
                .tag(AppTab.insights)
            WalletView()
                .tabItem { Label(AppTab.wallet.title, systemImage: AppTab.wallet.symbol) }
                .tag(AppTab.wallet)
            TogetherView()
                .tabItem { Label(AppTab.together.title, systemImage: AppTab.together.symbol) }
                .tag(AppTab.together)
        }
    }

    /// Catches up recurring transactions, reschedules reminders and rewrites the widget snapshot.
    private func refreshData() {
        RecurringService.generateDueTransactions(in: context)
        NotificationService.shared.reschedule(context: context, settings: settings)
        SnapshotService.refresh(context: context, settings: settings)
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
