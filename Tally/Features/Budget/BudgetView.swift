import SwiftUI
import SwiftData
import TallyCore

/// Sheets the Plan tab can present.
enum BudgetPlanSheet: Identifiable {
    case limits
    case newCategory
    case setLimit(Category, Decimal)

    var id: String {
        switch self {
        case .limits: return "limits"
        case .newCategory: return "new-category"
        case .setLimit(let category, _): return "limit-\(category.id.uuidString)"
        }
    }
}

/// The Plan tab: what is left to spend, category by category.
struct BudgetView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var period: BudgetPeriod
    @State private var didSyncPeriod = false
    @State private var sheet: BudgetPlanSheet?

    init() {
        _period = State(initialValue: AppSettings.shared.currentPeriod)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                mainContent
                AddButton { router.showAdd(.expense) }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .navigationDestination(for: Category.self) { category in
                BudgetCategoryDetailView(category: category, period: period)
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .onAppear {
            if !didSyncPeriod {
                didSyncPeriod = true
                period = settings.currentPeriod
            }
        }
        .onChange(of: settings.periodSettings) { _, _ in
            period = settings.currentPeriod
        }
    }

    // MARK: Toolbar and sheets

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                settings.hideAmounts.toggle()
            } label: {
                Image(systemName: settings.hideAmounts ? "eye.slash" : "eye")
            }
            .accessibilityLabel(settings.hideAmounts ? Text("Show amounts") : Text("Hide amounts"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                router.sheet = .settings
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: BudgetPlanSheet) -> some View {
        switch item {
        case .limits:
            BudgetLimitsEditorView()
        case .newCategory:
            CategoryEditorView(category: nil)
        case .setLimit(let category, let spent):
            BudgetSetLimitSheet(category: category, spent: spent)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var mainContent: some View {
        if categories.isEmpty {
            emptyState
        } else {
            let summary: PeriodSummary = BudgetService.summary(
                for: period,
                transactions: transactions,
                categories: categories,
                settings: settings
            )
            planScroll(summary)
        }
    }

    private var emptyState: some View {
        ScrollView {
            EmptyStateView(
                symbol: "square.grid.2x2",
                title: "No categories yet",
                message: "Categories are how Tally groups your spending. Add a few, then give each a limit to build your plan.",
                actionTitle: "Add a category",
                action: { sheet = .newCategory }
            )
            .padding(.top, 48)
        }
        .tallyScreen()
    }

    private func planScroll(_ summary: PeriodSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    PeriodNavigator(period: $period)
                    Spacer()
                }
                heroSection(summary)
                budgetedSection(summary)
                unbudgetedSection(summary)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
        .tallyScreen()
    }

    @ViewBuilder
    private func heroSection(_ summary: PeriodSummary) -> some View {
        if summary.totalBudget > 0 {
            BudgetHeroCard(summary: summary)
        } else {
            BudgetSetupPromptCard { sheet = .limits }
            BudgetStatsRow(summary: summary)
                .tallyCard()
        }
    }

    // MARK: Budgeted

    private var budgetedCategories: [Category] {
        categories
            .filter { !$0.isArchived && $0.kind == .expense && $0.budgetLimit > 0 }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @ViewBuilder
    private func budgetedSection(_ summary: PeriodSummary) -> some View {
        let rows: [Category] = budgetedCategories
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Budgeted") {
                    Button("Edit budget") { sheet = .limits }
                }
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, category in
                        if index > 0 { Rule().padding(.leading, 60) }
                        budgetedRow(category, summary: summary)
                    }
                }
                .tallyCard(padding: 0)
            }
        }
    }

    @ViewBuilder
    private func budgetedRow(_ category: Category, summary: PeriodSummary) -> some View {
        if let status = summary.status(for: category.id) {
            NavigationLink(value: category) {
                BudgetCategoryRow(category: category, status: status)
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Not budgeted

    private func unbudgetedEntries(_ summary: PeriodSummary) -> [BudgetUnbudgetedEntry] {
        let budgetedIDs: Set<UUID> = Set(summary.categoryStatuses.map { $0.id })
        var entries: [BudgetUnbudgetedEntry] = []
        for category in categories where category.kind == .expense && !budgetedIDs.contains(category.id) {
            let key: UUID? = category.id
            let spent: Decimal = summary.spentByCategory[key] ?? 0
            if spent > 0 {
                entries.append(BudgetUnbudgetedEntry(category: category, spent: spent))
            }
        }
        entries.sort { $0.spent > $1.spent }
        let noCategory: UUID? = nil
        let uncategorized: Decimal = summary.spentByCategory[noCategory] ?? 0
        if uncategorized > 0 {
            entries.append(BudgetUnbudgetedEntry(category: nil, spent: uncategorized))
        }
        return entries
    }

    @ViewBuilder
    private func unbudgetedSection(_ summary: PeriodSummary) -> some View {
        let entries: [BudgetUnbudgetedEntry] = unbudgetedEntries(summary)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Not budgeted")
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Rule().padding(.leading, 60) }
                        BudgetUnbudgetedRow(entry: entry) { category in
                            sheet = .setLimit(category, entry.spent)
                        }
                        .padding(.horizontal, Metrics.cardPadding)
                        .padding(.vertical, 12)
                    }
                }
                .tallyCard(padding: 0)
                Text("Spending here is not counted against a category limit, but it still reduces what is left to spend.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

#Preview {
    BudgetView()
        .previewEnvironment()
}
