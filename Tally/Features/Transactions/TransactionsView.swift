import SwiftUI
import SwiftData
import TallyCore

// MARK: - Supporting types

/// Filters the Ledger can apply on top of the period and search text.
struct LedgerFilter: Equatable {
    var kind: TransactionKind? = nil
    var categoryID: UUID? = nil
    var accountID: UUID? = nil
    var splitOnly: Bool = false

    var isActive: Bool {
        kind != nil || categoryID != nil || accountID != nil || splitOnly
    }
}

/// One day's worth of transactions, newest first.
struct LedgerDayGroup: Identifiable {
    let day: Date
    let transactions: [Transaction]

    var id: Date { day }

    /// Income minus expenses for the day. Transfers don't move the total.
    var net: Decimal {
        var total: Decimal = 0
        for transaction in transactions {
            switch transaction.kind {
            case .income: total += transaction.amount
            case .expense: total -= transaction.amount
            case .transfer: break
            }
        }
        return total
    }

    static func make(from transactions: [Transaction]) -> [LedgerDayGroup] {
        let calendar = Calendar.current
        var buckets: [Date: [Transaction]] = [:]
        for transaction in transactions {
            let day = calendar.startOfDay(for: transaction.date)
            buckets[day, default: []].append(transaction)
        }
        let days: [Date] = buckets.keys.sorted(by: >)
        return days.map { day in
            let items: [Transaction] = (buckets[day] ?? []).sorted { $0.date > $1.date }
            return LedgerDayGroup(day: day, transactions: items)
        }
    }
}

struct LedgerTotals {
    var income: Decimal = 0
    var expense: Decimal = 0
    var net: Decimal { income - expense }

    init(transactions: [Transaction]) {
        for transaction in transactions {
            switch transaction.kind {
            case .income: income += transaction.amount
            case .expense: expense += transaction.amount
            case .transfer: break
            }
        }
    }
}

// MARK: - Ledger

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(filter: #Predicate<Category> { !$0.isArchived }, sort: \Category.sortOrder)
    private var categories: [Category]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var period: BudgetPeriod
    @State private var showsAllTime = false
    @State private var searchText = ""
    @State private var filter = LedgerFilter()
    @State private var editing: Transaction?

    init() {
        _period = State(initialValue: AppSettings.shared.currentPeriod)
    }

    var body: some View {
        let visible: [Transaction] = visibleTransactions()
        let groups: [LedgerDayGroup] = LedgerDayGroup.make(from: visible)
        let totals = LedgerTotals(transactions: visible)

        NavigationStack {
            VStack(spacing: 0) {
                periodBar
                if groups.isEmpty {
                    emptyContent
                } else {
                    listContent(groups: groups, totals: totals)
                }
            }
            .tallyScreen()
            .navigationTitle("Ledger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        RecurringListView()
                    } label: {
                        Label("Recurring", systemImage: "repeat")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
            .searchable(text: $searchText, prompt: "Search title, note or category")
            .overlay(alignment: .bottomTrailing) {
                AddButton { router.showAdd(.expense) }
                    .padding(.trailing, Metrics.screenPadding)
                    .padding(.bottom, Metrics.screenPadding)
            }
            .sheet(item: $editing) { transaction in
                TransactionEditorView(transaction: transaction)
            }
        }
    }

    // MARK: Period bar

    private var periodBar: some View {
        HStack(spacing: 8) {
            if showsAllTime {
                Text("All time")
                    .font(.headlineSerif)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
            } else {
                PeriodNavigator(period: $period)
                    .frame(maxWidth: .infinity)
            }
            Button {
                showsAllTime.toggle()
            } label: {
                Text(showsAllTime ? "By period" : "All time")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.vertical, 6)
    }

    // MARK: Filter menu

    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $filter.kind) {
                Text("All types").tag(TransactionKind?.none)
                ForEach(TransactionKind.allCases) { kind in
                    Text(kind.displayName).tag(TransactionKind?.some(kind))
                }
            }
            Picker("Category", selection: $filter.categoryID) {
                Text("All categories").tag(UUID?.none)
                ForEach(categories) { category in
                    Text(category.name).tag(UUID?.some(category.id))
                }
            }
            Picker("Account", selection: $filter.accountID) {
                Text("All accounts").tag(UUID?.none)
                ForEach(accounts) { account in
                    Text(account.name).tag(UUID?.some(account.id))
                }
            }
            Toggle("Split only", isOn: $filter.splitOnly)
            if filter.isActive {
                Button("Clear filters", role: .destructive) {
                    filter = LedgerFilter()
                }
            }
        } label: {
            Image(systemName: filter.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter")
    }

    // MARK: Content

    private func listContent(groups: [LedgerDayGroup], totals: LedgerTotals) -> some View {
        List {
            Section {
                LedgerTotalsCard(totals: totals)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.transactions) { transaction in
                        row(for: transaction)
                    }
                } header: {
                    LedgerDayHeader(group: group)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 88, for: .scrollContent)
    }

    private func row(for transaction: Transaction) -> some View {
        Button {
            editing = transaction
        } label: {
            LedgerRow(transaction: transaction)
        }
        .buttonStyle(.plain)
        .listRowBackground(Palette.surface)
        .listRowSeparatorTint(Palette.rule)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                delete(transaction)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                duplicate(transaction)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(Palette.accent)
        }
    }

    private var emptyContent: some View {
        VStack {
            Spacer()
            if searchText.isEmpty && !filter.isActive {
                EmptyStateView(
                    symbol: "list.bullet.rectangle",
                    title: showsAllTime ? "No transactions yet" : "A quiet period",
                    message: showsAllTime
                        ? "Add your first expense or paycheck and it will show up here."
                        : "Nothing has been recorded in this period.",
                    actionTitle: "Add a transaction",
                    action: { router.showAdd(.expense) }
                )
            } else {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "Nothing matches",
                    message: "Try a different search, or loosen the filters.",
                    actionTitle: "Clear search and filters",
                    action: {
                        searchText = ""
                        filter = LedgerFilter()
                    }
                )
            }
            Spacer()
            Spacer()
        }
    }

    // MARK: Filtering

    private func visibleTransactions() -> [Transaction] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result: [Transaction] = []
        for transaction in transactions {
            if matches(transaction, query: query) {
                result.append(transaction)
            }
        }
        return result
    }

    private func matches(_ transaction: Transaction, query: String) -> Bool {
        if !showsAllTime && !period.contains(transaction.date) { return false }
        if let kind = filter.kind, transaction.kind != kind { return false }
        if let categoryID = filter.categoryID, transaction.category?.id != categoryID { return false }
        if let accountID = filter.accountID {
            let fromMatch = transaction.account?.id == accountID
            let toMatch = transaction.toAccount?.id == accountID
            if !fromMatch && !toMatch { return false }
        }
        if filter.splitOnly && !transaction.isSplit { return false }
        if !query.isEmpty {
            let haystacks: [String] = [
                transaction.title,
                transaction.note,
                transaction.category?.name ?? ""
            ]
            var found = false
            for text in haystacks where text.lowercased().contains(query) {
                found = true
                break
            }
            if !found { return false }
        }
        return true
    }

    // MARK: Actions

    private func delete(_ transaction: Transaction) {
        context.delete(transaction)
        try? context.save()
    }

    private func duplicate(_ transaction: Transaction) {
        let copy = Transaction(
            amount: transaction.amount,
            kind: transaction.kind,
            title: transaction.title,
            date: Date(),
            category: transaction.category,
            account: transaction.account,
            note: transaction.note
        )
        copy.toAccount = transaction.toAccount
        copy.paidBy = transaction.paidBy
        copy.splitMethod = transaction.splitMethod
        context.insert(copy)
        for share in transaction.splitShares ?? [] {
            let newShare = SplitShare(amount: share.amount, weight: share.weight, member: share.member)
            context.insert(newShare)
            newShare.transaction = copy
        }
        try? context.save()
    }
}

// MARK: - Header card

struct LedgerTotalsCard: View {
    let totals: LedgerTotals

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            column(title: "In", amount: totals.income, colored: false)
            divider
            column(title: "Out", amount: totals.expense, colored: false)
            divider
            column(title: "Net", amount: totals.net, colored: true)
        }
        .tallyCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.rule)
            .frame(width: Metrics.hairline)
            .padding(.vertical, 2)
    }

    private func column(title: String, amount: Decimal, colored: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Overline(title)
            MoneyText(amount: amount, showsSign: colored, font: .display(19), colored: colored)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}

// MARK: - Day header

struct LedgerDayHeader: View {
    let group: LedgerDayGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dayName)
                .font(.headlineSerif)
                .foregroundStyle(Palette.ink)
            Text(dateText)
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            if group.net != 0 {
                MoneyText(amount: group.net, showsSign: true, font: .amountSmall)
            }
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }

    private var dayName: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(group.day) { return "Today" }
        if calendar.isDateInYesterday(group.day) { return "Yesterday" }
        return group.day.formatted(.dateTime.weekday(.wide))
    }

    private var dateText: String {
        let calendar = Calendar.current
        let sameYear = calendar.isDate(group.day, equalTo: Date(), toGranularity: .year)
        if sameYear {
            return group.day.formatted(.dateTime.month(.abbreviated).day())
        }
        return group.day.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - Row

struct LedgerRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.displayTitle)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                subtitle
            }
            Spacer(minLength: 8)
            amountView
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if transaction.kind == .transfer {
            CategoryIcon(symbol: "arrow.left.arrow.right", colorHex: "#4A5560")
        } else {
            CategoryIcon(category: transaction.category)
        }
    }

    private var subtitle: some View {
        HStack(spacing: 4) {
            Text(subtitleText)
                .lineLimit(1)
            if transaction.recurringTemplate != nil {
                Image(systemName: "repeat")
                    .accessibilityLabel("Repeats")
            }
            if transaction.isSplit {
                Image(systemName: "person.2")
                    .accessibilityLabel("Split")
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.inkSecondary)
    }

    private var subtitleText: String {
        if transaction.kind == .transfer {
            let from: String = transaction.account?.name ?? "No account"
            let to: String = transaction.toAccount?.name ?? "No account"
            return "\(from) \u{2192} \(to)"
        }
        var parts: [String] = []
        if let name = transaction.category?.name { parts.append(name) }
        if let name = transaction.account?.name { parts.append(name) }
        if parts.isEmpty { return transaction.kind.displayName }
        return parts.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private var amountView: some View {
        switch transaction.kind {
        case .expense:
            MoneyText(amount: -transaction.amount, showsSign: true)
        case .income:
            MoneyText(amount: transaction.amount, showsSign: true, colored: true)
        case .transfer:
            HStack(spacing: 5) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkTertiary)
                MoneyText(amount: transaction.amount)
            }
        }
    }
}

#Preview {
    TransactionsView()
        .previewEnvironment()
}
