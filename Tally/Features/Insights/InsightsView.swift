import SwiftUI
import SwiftData
import TallyCore

/// Charts and totals for one budget period, plus six-period trends.
struct InsightsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ProStore.self) private var store
    @Environment(AppRouter.self) private var router

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var accounts: [Account]

    /// Nil follows the current period from settings until the user navigates.
    @State private var selectedPeriod: BudgetPeriod?

    private var periodBinding: Binding<BudgetPeriod> {
        Binding(
            get: { selectedPeriod ?? settings.currentPeriod },
            set: { selectedPeriod = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if transactions.isEmpty {
                    emptyState
                } else {
                    loaded(makeData())
                }
            }
            .tallyScreen()
            .navigationTitle("Insights")
        }
    }

    private func makeData() -> InsightsData {
        InsightsData(
            transactions: transactions,
            categories: categories,
            accounts: accounts,
            period: periodBinding.wrappedValue,
            settings: settings
        )
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "chart.bar.xaxis",
            title: "Nothing to chart yet",
            message: "Add a few transactions and your spending patterns will show up here.",
            actionTitle: "Add a transaction",
            action: { router.showAdd() }
        )
        .padding(.top, 60)
    }

    private func loaded(_ data: InsightsData) -> some View {
        let locked: Bool = !store.isUnlocked(.advancedInsights)
        return VStack(spacing: 20) {
            PeriodNavigator(period: periodBinding)
                .frame(maxWidth: .infinity)
            InsightsSummaryCard(data: data)
            InsightsCategoryCard(data: data)
            InsightsIncomeSpendingCard(data: data)
            InsightsPaceCard(data: data)
                .insightsProGate(locked: locked)
            InsightsPayeesCard(data: data)
            InsightsNetWorthCard(data: data)
                .insightsProGate(locked: locked)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.vertical, 12)
    }
}

#Preview {
    InsightsView()
        .previewEnvironment()
}
