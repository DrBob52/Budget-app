import SwiftUI
import SwiftData
import TallyCore

/// Accounts, net worth and savings goals.
struct WalletView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(ProStore.self) private var store

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \SavingsGoal.sortOrder) private var goals: [SavingsGoal]

    @State private var showNewAccount = false
    @State private var showNewGoal = false
    @State private var archivedExpanded = false

    /// Free plan allows this many active goals.
    private let freeGoalLimit = 2

    var body: some View {
        NavigationStack {
            List {
                Section {
                    heroCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                accountsSection
                goalsSection
                if !archivedAccounts.isEmpty || !archivedGoals.isEmpty {
                    archivedSection
                }
            }
            .listStyle(.insetGrouped)
            .tallyScreen()
            .navigationTitle("Wallet")
            .toolbar {
                if activeAccounts.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showNewAccount = true
                        } label: {
                            Label("New account", systemImage: "building.columns")
                        }
                        Button {
                            requestNewGoal()
                        } label: {
                            Label("New goal", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add account or goal")
                }
            }
            .sheet(isPresented: $showNewAccount) {
                AccountEditorView(account: nil)
            }
            .sheet(isPresented: $showNewGoal) {
                GoalEditorView(goal: nil)
            }
        }
    }

    // MARK: - Derived data

    private var activeAccounts: [Account] {
        accounts
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private var archivedAccounts: [Account] {
        accounts.filter { $0.isArchived }
    }

    private var activeGoals: [SavingsGoal] {
        goals
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private var archivedGoals: [SavingsGoal] {
        goals.filter { $0.isArchived }
    }

    private var countedAccounts: [Account] {
        accounts.filter { !$0.isArchived && $0.includeInNetWorth }
    }

    private var netWorth: Decimal {
        BudgetService.netWorth(accounts: accounts)
    }

    /// Positive balances. Together with liabilities this adds up to the net worth.
    private var assetsTotal: Decimal {
        countedAccounts.reduce(Decimal(0)) { partial, account in
            partial + max(account.balance, 0)
        }
    }

    /// Money owed: credit cards and any account below zero.
    private var liabilitiesTotal: Decimal {
        countedAccounts.reduce(Decimal(0)) { partial, account in
            partial + max(-account.balance, 0)
        }
    }

    private var goalLimitReached: Bool {
        !store.isUnlocked(.unlimitedGoals) && activeGoals.count >= freeGoalLimit
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Overline("Net worth")
            MoneyText(amount: netWorth, font: Font.display(40), colored: netWorth < 0)
            Rule()
            HStack(alignment: .top, spacing: 0) {
                heroColumn(title: "Assets", amount: assetsTotal, tint: Palette.accent)
                heroColumn(title: "Liabilities", amount: liabilitiesTotal, tint: Palette.negative)
            }
            Text(heroFootnote)
                .font(.caption)
                .foregroundStyle(Palette.inkTertiary)
        }
        .tallyCard()
    }

    private func heroColumn(title: String, amount: Decimal, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
            MoneyText(amount: amount, font: Font.system(.title3, design: .serif).weight(.medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroFootnote: String {
        let count = countedAccounts.count
        if count == 0 { return "Add an account to see your net worth." }
        return count == 1 ? "Across 1 account" : "Across \(count) accounts"
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        Section {
            if activeAccounts.isEmpty {
                EmptyStateView(
                    symbol: "wallet.pass",
                    title: "No accounts yet",
                    message: "Add the places your money lives, like a checking account, cash or a credit card.",
                    actionTitle: "Add an account",
                    action: { showNewAccount = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(activeAccounts) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        AccountRow(account: account, isDefault: settings.defaultAccountID == account.id)
                    }
                    .listRowBackground(Palette.surface)
                    .listRowSeparatorTint(Palette.rule)
                }
                .onMove(perform: moveAccounts)
            }
        } header: {
            SectionHeader("Accounts") {
                Button("New account") { showNewAccount = true }
            }
            .textCase(nil)
        }
    }

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        var ordered = activeAccounts
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, account) in ordered.enumerated() {
            account.sortOrder = index
        }
        try? context.save()
    }

    // MARK: - Goals

    private var goalsSection: some View {
        Section {
            if activeGoals.isEmpty {
                EmptyStateView(
                    symbol: "flag",
                    title: "No goals yet",
                    message: "Set aside money for something specific, a trip, a cushion or a big purchase, and watch it fill up.",
                    actionTitle: "Create a goal",
                    action: { requestNewGoal() }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(activeGoals) { goal in
                    NavigationLink {
                        GoalDetailView(goal: goal)
                    } label: {
                        GoalCard(goal: goal)
                    }
                    .listRowBackground(Palette.surface)
                    .listRowSeparatorTint(Palette.rule)
                }
            }
        } header: {
            SectionHeader("Savings goals") {
                Button("New goal") { requestNewGoal() }
            }
            .textCase(nil)
        } footer: {
            if goalLimitReached {
                Text("The free plan includes \(freeGoalLimit) active goals. Archive one or unlock Tally Pro for more.")
                    .font(.caption)
                    .foregroundStyle(Palette.inkTertiary)
                    .textCase(nil)
            }
        }
    }

    private func requestNewGoal() {
        if goalLimitReached {
            router.sheet = .paywall
        } else {
            showNewGoal = true
        }
    }

    // MARK: - Archived

    private var archivedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $archivedExpanded) {
                ForEach(archivedAccounts) { account in
                    archivedAccountRow(account)
                }
                ForEach(archivedGoals) { goal in
                    archivedGoalRow(goal)
                }
            } label: {
                Text("Archived (\(archivedAccounts.count + archivedGoals.count))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
        }
    }

    private func archivedAccountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(symbol: account.symbol, colorHex: account.colorHex, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(account.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            Button("Restore") {
                restore(account)
            }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Palette.accent)
        }
    }

    private func archivedGoalRow(_ goal: SavingsGoal) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(symbol: goal.symbol, colorHex: goal.colorHex, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text("Savings goal")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            Button("Restore") {
                restore(goal)
            }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Palette.accent)
        }
    }

    private func restore(_ account: Account) {
        let last = accounts.map { $0.sortOrder }.max() ?? 0
        account.sortOrder = last + 1
        account.isArchived = false
        try? context.save()
    }

    private func restore(_ goal: SavingsGoal) {
        if goalLimitReached {
            router.sheet = .paywall
            return
        }
        let last = goals.map { $0.sortOrder }.max() ?? 0
        goal.sortOrder = last + 1
        goal.isArchived = false
        try? context.save()
    }
}

#Preview {
    WalletView()
        .previewEnvironment()
}
