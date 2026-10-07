import SwiftUI
import SwiftData
import TallyCore

/// Shared spending with a partner, roommates or a trip group: who paid what and how to settle up.
struct TogetherView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(ProStore.self) private var store

    @Query(sort: \Member.createdAt) private var members: [Member]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Settlement.date, order: .reverse) private var settlements: [Settlement]

    @State private var showSetup = false
    @State private var editingTransaction: Transaction?
    @State private var pendingPayment: SettleUpTransfer?
    @State private var confirmingPayment = false
    @State private var showAllActivity = false

    private let collapsedActivityCount = 6

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Together")
                .toolbar { toolbarContent }
                .tallyScreen()
                .sheet(isPresented: $showSetup) {
                    TogetherSetupView()
                }
                .sheet(item: $editingTransaction) { transaction in
                    TransactionEditorView(transaction: transaction)
                }
                .confirmationDialog(
                    "Record this payment?",
                    isPresented: $confirmingPayment,
                    titleVisibility: .visible,
                    presenting: pendingPayment
                ) { transfer in
                    Button("Mark paid") { record(transfer) }
                    Button("Cancel", role: .cancel) {}
                } message: { transfer in
                    Text(paymentMessage(transfer))
                }
        }
    }

    // MARK: - Derived data

    private var memberByID: [UUID: Member] {
        Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var me: Member? { members.first(where: { $0.isMe }) }

    private var balances: [UUID: Decimal] {
        BudgetService.memberBalances(transactions: transactions, settlements: settlements)
    }

    private var suggestedPayments: [SettleUpTransfer] {
        let lookup = memberByID
        return SplitCalculator.settleUp(balances: balances).filter { transfer in
            lookup[transfer.fromID] != nil && lookup[transfer.toID] != nil
        }
    }

    private var splitTransactions: [Transaction] {
        transactions.filter { $0.isSplit }
    }

    private var visibleActivity: [Transaction] {
        let all = splitTransactions
        if showAllActivity || all.count <= collapsedActivityCount { return all }
        return Array(all.prefix(collapsedActivityCount))
    }

    private func balance(for member: Member) -> Decimal {
        balances[member.id] ?? 0
    }

    private func paidThisPeriod(_ member: Member) -> Decimal {
        let period: BudgetPeriod = settings.currentPeriod
        var total: Decimal = 0
        for item in member.paidTransactions ?? [] {
            if item.kind == .expense && period.contains(item.date) {
                total += item.amount
            }
        }
        return total
    }

    // MARK: - Layout

    @ViewBuilder
    private var mainContent: some View {
        if members.count < 2 {
            onboarding
        } else {
            sharedList
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if members.count >= 2 {
                ShareLink(item: summaryText, subject: Text("Shared budget summary")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share summary")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if members.count >= 2 {
                NavigationLink {
                    TogetherMembersView()
                } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("People")
            }
        }
    }

    private var onboarding: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Overline("Shared spending")
                    Text("Keep a running tab with the people you spend with")
                        .font(.titleSerif)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Log an expense, say who paid and how it divides. Tally keeps a running balance for everyone and tells you the simplest way to even things out.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Rule()

                    onboardingPoint(symbol: "person.2", text: "Add a partner, roommates or a trip group.")
                    onboardingPoint(symbol: "divide", text: "Split any expense equally, by amount, percentage or shares.")
                    onboardingPoint(symbol: "arrow.left.arrow.right", text: "See who owes whom and record repayments.")
                    onboardingPoint(symbol: "square.and.arrow.up", text: "Share a plain-text summary whenever you like.")

                    Button {
                        startSetup()
                    } label: {
                        Text("Set up")
                    }
                    .buttonStyle(.tallyPrimary)
                    .padding(.top, 4)

                    if !store.isUnlocked(.sharedBudgets) {
                        Text("Adding people is part of Tally Pro.")
                            .font(.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
                .tallyCard()
            }
            .padding(Metrics.screenPadding)
        }
    }

    private func onboardingPoint(symbol: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Palette.accent)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sharedList: some View {
        List {
            Section {
                TogetherBalanceGrid(members: members, balances: balances)
                    .togetherCardRow()
            } header: {
                sectionHeader("Balances")
            }

            Section {
                suggestionRows
            } header: {
                sectionHeader("Suggested payments")
            }

            Section {
                activityRows
            } header: {
                sectionHeader("Shared activity")
            }

            Section {
                spendingCard
                    .togetherCardRow()
            } header: {
                sectionHeader("Paid this period")
            }

            Section {
                historyRows
            } header: {
                sectionHeader("Settlement history")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        SectionHeader(title)
            .textCase(nil)
    }

    // MARK: - Suggested payments

    @ViewBuilder
    private var suggestionRows: some View {
        let transfers: [SettleUpTransfer] = suggestedPayments
        let lookup: [UUID: Member] = memberByID
        if transfers.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Palette.accent)
                Text("Nobody owes anyone right now.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
        } else {
            ForEach(transfers) { transfer in
                if let from = lookup[transfer.fromID], let to = lookup[transfer.toID] {
                    TogetherSuggestionRow(from: from, to: to, amount: transfer.amount) {
                        pendingPayment = transfer
                        confirmingPayment = true
                    }
                    .listRowBackground(Palette.surface)
                }
            }
        }
    }

    private func paymentMessage(_ transfer: SettleUpTransfer) -> String {
        let lookup: [UUID: Member] = memberByID
        let from: String = lookup[transfer.fromID]?.name ?? String(localized: "Someone")
        let to: String = lookup[transfer.toID]?.name ?? String(localized: "someone")
        return String(localized: "\(from) paid \(to) \(settings.format(transfer.amount)). This adds a repayment to the history and updates everyone's balance.")
    }

    private func record(_ transfer: SettleUpTransfer) {
        let lookup: [UUID: Member] = memberByID
        guard let from = lookup[transfer.fromID], let to = lookup[transfer.toID] else { return }
        let settlement = Settlement(amount: transfer.amount, from: from, to: to, date: Date(), note: String(localized: "Settled up"))
        context.insert(settlement)
        try? context.save()
        pendingPayment = nil
    }

    // MARK: - Activity

    @ViewBuilder
    private var activityRows: some View {
        let all: [Transaction] = splitTransactions
        if all.isEmpty {
            Text("Nothing shared yet. Add an expense, choose who paid and how it divides.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Palette.surface)
        } else {
            ForEach(visibleActivity) { transaction in
                Button {
                    editingTransaction = transaction
                } label: {
                    TogetherActivityRow(transaction: transaction, myID: me?.id)
                }
                .buttonStyle(.plain)
                .listRowBackground(Palette.surface)
            }
            if all.count > collapsedActivityCount {
                Button {
                    withAnimation { showAllActivity.toggle() }
                } label: {
                    if showAllActivity {
                        Text("Show fewer")
                    } else {
                        Text("Show all \(all.count)")
                    }
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.accent)
                .listRowBackground(Palette.surface)
            }
        }
        Button {
            router.showAdd(.expense)
        } label: {
            Label("Add shared expense", systemImage: "plus")
        }
        .buttonStyle(.tallySecondary)
        .togetherCardRow()
    }

    // MARK: - Spending bars

    private var spendingCard: some View {
        let period: BudgetPeriod = settings.currentPeriod
        let totals: [TogetherSpendEntry] = members.map { member in
            TogetherSpendEntry(member: member, amount: paidThisPeriod(member))
        }
        let maxAmount: Decimal = totals.map { $0.amount }.max() ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            Text(period.title())
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
            ForEach(totals) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        MemberAvatar(member: entry.member, size: 24)
                        (entry.member.isMe ? Text("\(entry.member.name) (you)") : Text(entry.member.name))
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        MoneyText(amount: entry.amount, font: .amountSmall)
                    }
                    BudgetBar(
                        progress: maxAmount > 0 ? (entry.amount / maxAmount).doubleValue : 0,
                        height: 6,
                        tint: Color(hex: entry.member.colorHex)
                    )
                }
            }
        }
        .tallyCard()
    }

    // MARK: - History

    @ViewBuilder
    private var historyRows: some View {
        if settlements.isEmpty {
            Text("Repayments you mark as paid will appear here.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Palette.surface)
        } else {
            ForEach(settlements) { settlement in
                TogetherHistoryRow(settlement: settlement)
                    .listRowBackground(Palette.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(settlement)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func delete(_ settlement: Settlement) {
        context.delete(settlement)
        try? context.save()
    }

    // MARK: - Actions

    private func startSetup() {
        if store.isUnlocked(.sharedBudgets) {
            showSetup = true
        } else {
            router.sheet = .paywall
        }
    }

    private var summaryText: String {
        TogetherSummaryBuilder.text(
            members: members,
            balances: balances,
            transfers: suggestedPayments,
            settings: settings
        )
    }
}

// MARK: - Row helpers

extension View {
    /// Clear list row that hosts a card or button, without separators or inset chrome.
    fileprivate func togetherCardRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
}

private struct TogetherSpendEntry: Identifiable {
    let member: Member
    let amount: Decimal
    var id: UUID { member.id }
}

private enum TogetherBalanceState {
    case owed
    case owes
    case square

    init(_ amount: Decimal) {
        let unit: Decimal = Decimal.unit(scale: 2)
        if amount >= unit {
            self = .owed
        } else if amount <= -unit {
            self = .owes
        } else {
            self = .square
        }
    }

    var label: String {
        switch self {
        case .owed: return String(localized: "Is owed")
        case .owes: return String(localized: "Owes")
        case .square: return String(localized: "All square")
        }
    }

    var tint: Color {
        switch self {
        case .owed: return Palette.accent
        case .owes: return Palette.negative
        case .square: return Palette.inkSecondary
        }
    }
}

/// Grid of one card per member: owed (accent), owes (terracotta) or all square.
struct TogetherBalanceGrid: View {
    let members: [Member]
    let balances: [UUID: Decimal]

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(members) { member in
                card(for: member)
            }
        }
    }

    private func card(for member: Member) -> some View {
        let amount: Decimal = balances[member.id] ?? 0
        let state = TogetherBalanceState(amount)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MemberAvatar(member: member, size: 28)
                (member.isMe ? Text("You") : Text(member.name))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            Text(state.label.localizedUppercase)
                .font(.overline)
                .tracking(1.2)
                .foregroundStyle(state.tint)
            if state == .square {
                Text("Settled")
                    .font(.display(22, weight: .regular))
                    .foregroundStyle(Palette.inkTertiary)
            } else {
                MoneyText(amount: amount.magnitudeValue, font: .display(24))
            }
        }
        .tallyCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct TogetherSuggestionRow: View {
    let from: Member
    let to: Member
    let amount: Decimal
    let onMarkPaid: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MemberAvatar(member: from, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(from.name) \u{2192} \(to.name)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                MoneyText(amount: amount, font: .amountSmall)
            }
            Spacer(minLength: 8)
            Button("Mark paid", action: onMarkPaid)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Palette.accent)
        }
        .padding(.vertical, 2)
    }
}

struct TogetherActivityRow: View {
    let transaction: Transaction
    let myID: UUID?

    var body: some View {
        HStack(spacing: 12) {
            if let payer = transaction.paidBy {
                MemberAvatar(member: payer, size: 34)
            } else {
                CategoryIcon(category: transaction.category, size: 34)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.displayTitle)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                MoneyText(amount: transaction.amount)
                shareLine
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let date: String = transaction.date.formatted(.dateTime.month(.abbreviated).day())
        if let payer = transaction.paidBy {
            return String(localized: "\(payer.name) paid \u{00B7} \(date)")
        }
        return date
    }

    private var myShare: Decimal? {
        guard let myID else { return nil }
        var total: Decimal = 0
        var found = false
        for share in transaction.splitShares ?? [] {
            if share.member?.id == myID {
                total += share.amount
                found = true
            }
        }
        return found ? total : nil
    }

    @ViewBuilder
    private var shareLine: some View {
        if let share = myShare {
            HStack(spacing: 4) {
                Text("Your share")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                MoneyText(amount: share, font: Font.system(.caption, design: .serif).monospacedDigit())
            }
        } else {
            Text("Not in your share")
                .font(.caption)
                .foregroundStyle(Palette.inkTertiary)
        }
    }
}

struct TogetherHistoryRow: View {
    let settlement: Settlement

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(fromName) \u{2192} \(toName)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            MoneyText(amount: settlement.amount, font: .amountSmall)
        }
        .accessibilityElement(children: .combine)
    }

    private var fromName: String { settlement.from?.name ?? String(localized: "Someone") }
    private var toName: String { settlement.to?.name ?? String(localized: "someone") }

    private var detail: String {
        let date: String = settlement.date.formatted(.dateTime.month(.abbreviated).day().year())
        if settlement.note.isEmpty { return date }
        return "\(date) \u{00B7} \(settlement.note)"
    }
}

/// Plain-text summary of balances and suggested payments, for the share sheet.
enum TogetherSummaryBuilder {
    static func text(
        members: [Member],
        balances: [UUID: Decimal],
        transfers: [SettleUpTransfer],
        settings: AppSettings
    ) -> String {
        let names: [UUID: String] = Dictionary(
            members.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let unit: Decimal = Decimal.unit(scale: 2)
        var lines: [String] = []
        lines.append(String(localized: "Shared budget summary"))
        lines.append(Date().formatted(.dateTime.month(.wide).day().year()))
        lines.append("")
        lines.append(String(localized: "Balances"))
        for member in members {
            let amount: Decimal = balances[member.id] ?? 0
            if amount >= unit {
                lines.append(String(localized: "- \(member.name) is owed \(settings.format(amount))"))
            } else if amount <= -unit {
                lines.append(String(localized: "- \(member.name) owes \(settings.format(amount.magnitudeValue))"))
            } else {
                lines.append(String(localized: "- \(member.name) is all square"))
            }
        }
        lines.append("")
        if transfers.isEmpty {
            lines.append(String(localized: "Nothing to settle right now."))
        } else {
            lines.append(String(localized: "Suggested payments"))
            for transfer in transfers {
                let from: String = names[transfer.fromID] ?? String(localized: "Someone")
                let to: String = names[transfer.toID] ?? String(localized: "someone")
                lines.append("- \(from) \u{2192} \(to): \(settings.format(transfer.amount))")
            }
        }
        lines.append("")
        lines.append(String(localized: "Sent from Tally"))
        return lines.joined(separator: "\n")
    }
}

#Preview {
    TogetherView()
        .previewEnvironment()
}
