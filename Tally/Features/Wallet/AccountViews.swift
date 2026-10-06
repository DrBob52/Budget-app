import SwiftUI
import SwiftData
import TallyCore

// MARK: - Row

/// One account in the wallet list.
struct AccountRow: View {
    let account: Account
    let isDefault: Bool

    init(account: Account, isDefault: Bool = false) {
        self.account = account
        self.isDefault = isDefault
    }

    var body: some View {
        let balance: Decimal = account.balance
        HStack(spacing: 12) {
            CategoryIcon(symbol: account.symbol, colorHex: account.colorHex, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 8)
            MoneyText(amount: balance, font: Font.amount, colored: balance < 0)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts: [String] = [account.kind.displayName]
        if isDefault { parts.append("Default") }
        if !account.includeInNetWorth { parts.append("Not in net worth") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Detail

/// One line of an account's activity: an outgoing transaction or an incoming transfer.
private struct AccountActivityEntry: Identifiable {
    let transaction: Transaction
    let isIncomingTransfer: Bool

    var id: String {
        transaction.id.uuidString + (isIncomingTransfer ? "-in" : "-out")
    }

    /// Effect on this account's balance.
    var signedAmount: Decimal {
        if isIncomingTransfer { return transaction.amount }
        switch transaction.kind {
        case .income: return transaction.amount
        case .expense, .transfer: return -transaction.amount
        }
    }
}

struct AccountDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    let account: Account

    @State private var showEditor = false
    @State private var showTransfer = false
    @State private var showAdjust = false
    @State private var editingTransaction: Transaction?

    init(account: Account) {
        self.account = account
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                balanceCard
                actionButtons
                activitySection
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 12)
        }
        .tallyScreen()
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) {
            AccountEditorView(account: account)
        }
        .sheet(isPresented: $showTransfer) {
            TransactionEditorView(transaction: nil, initialKind: .transfer)
        }
        .sheet(isPresented: $showAdjust) {
            AccountAdjustBalanceView(account: account)
        }
        .sheet(item: $editingTransaction) { transaction in
            TransactionEditorView(transaction: transaction)
        }
        .onChange(of: account.isArchived) { _, archived in
            if archived { dismiss() }
        }
    }

    // MARK: Header

    private var balanceCard: some View {
        let balance: Decimal = account.balance
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CategoryIcon(symbol: account.symbol, colorHex: account.colorHex, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.headlineSerif)
                        .foregroundStyle(Palette.ink)
                    Text(account.kind.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                if settings.defaultAccountID == account.id {
                    Text("Default")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(Palette.accent)
                        .background(Palette.accent.opacity(0.12), in: Capsule())
                }
            }
            Overline("Balance")
            MoneyText(amount: balance, font: Font.display(40), colored: balance < 0)
            Rule()
            HStack {
                Text("Opening balance")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                MoneyText(amount: account.openingBalance, font: Font.amountSmall)
            }
            if !account.includeInNetWorth {
                Text("Not counted in your net worth")
                    .font(.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .tallyCard()
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showTransfer = true
            } label: {
                Label("Transfer", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.tallySecondary)

            Button {
                showAdjust = true
            } label: {
                Label("Adjust balance", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.tallySecondary)
        }
    }

    // MARK: Activity

    private var entries: [AccountActivityEntry] {
        var result: [AccountActivityEntry] = []
        for transaction in account.transactions ?? [] {
            result.append(AccountActivityEntry(transaction: transaction, isIncomingTransfer: false))
        }
        for transfer in account.incomingTransfers ?? [] where transfer.kind == .transfer {
            result.append(AccountActivityEntry(transaction: transfer, isIncomingTransfer: true))
        }
        result.sort { $0.transaction.date > $1.transaction.date }
        return result
    }

    private var activitySection: some View {
        let items: [AccountActivityEntry] = entries
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Activity")
            if items.isEmpty {
                Text("No activity on this account yet.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .tallyCard()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Rule() }
                        Button {
                            editingTransaction = entry.transaction
                        } label: {
                            AccountActivityRow(entry: entry, account: account)
                                .padding(.horizontal, Metrics.cardPadding)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .tallyCard(padding: 0)
            }
        }
    }
}

private struct AccountActivityRow: View {
    let entry: AccountActivityEntry
    let account: Account

    var body: some View {
        let transaction: Transaction = entry.transaction
        let isTransfer: Bool = transaction.kind == .transfer
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            MoneyText(
                amount: entry.signedAmount,
                showsSign: true,
                font: Font.amountSmall,
                colored: !isTransfer
            )
        }
    }

    @ViewBuilder
    private var icon: some View {
        let transaction: Transaction = entry.transaction
        if transaction.kind == .transfer {
            CategoryIcon(
                symbol: entry.isIncomingTransfer ? "arrow.down.left" : "arrow.up.right",
                colorHex: "#4A5560",
                size: 34
            )
        } else if let category = transaction.category {
            CategoryIcon(category: category, size: 34)
        } else {
            CategoryIcon(symbol: "slider.horizontal.3", colorHex: "#9C978C", size: 34)
        }
    }

    private var title: String {
        let transaction: Transaction = entry.transaction
        guard transaction.kind == .transfer else { return transaction.displayTitle }
        if entry.isIncomingTransfer {
            let source: String = transaction.account?.name ?? "another account"
            return "Transfer from \(source)"
        }
        let destination: String = transaction.toAccount?.name ?? "another account"
        return "Transfer to \(destination)"
    }

    private var subtitle: String {
        let transaction: Transaction = entry.transaction
        let dateText: String = transaction.date.formatted(date: .abbreviated, time: .omitted)
        if transaction.kind == .transfer {
            return dateText
        }
        if let category = transaction.category {
            return "\(dateText) \u{00B7} \(category.name)"
        }
        return dateText
    }
}

// MARK: - Adjust balance

/// Enter the balance the account really has; Tally records the difference.
struct AccountAdjustBalanceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    let account: Account

    @State private var actual: Decimal
    @State private var isNegative: Bool

    init(account: Account) {
        self.account = account
        let current: Decimal = account.balance
        _actual = State(initialValue: current.magnitudeValue)
        _isNegative = State(initialValue: current < 0)
    }

    private var signedActual: Decimal {
        isNegative ? -actual : actual
    }

    private var difference: Decimal {
        signedActual - account.balance
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Tally shows")
                            .foregroundStyle(Palette.inkSecondary)
                        Spacer()
                        MoneyText(amount: account.balance, font: Font.amount)
                    }
                } footer: {
                    Text("Enter what the account really holds, for example from your bank app.")
                }
                Section("Actual balance") {
                    AmountField(title: "0", amount: $actual, large: true)
                    Toggle("Negative balance (owed)", isOn: $isNegative)
                }
                Section {
                    HStack {
                        Text(differenceLabel)
                        Spacer()
                        MoneyText(amount: difference, showsSign: true, font: Font.amount, colored: true)
                    }
                } footer: {
                    Text("This is saved as a transaction called \u{201C}Balance adjustment\u{201D} with no category, dated today.")
                }
            }
            .tallyScreen()
            .navigationTitle("Adjust balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(difference == 0)
                }
            }
        }
    }

    private var differenceLabel: String {
        if difference == 0 { return "No difference" }
        return difference > 0 ? "Adds income of" : "Adds expense of"
    }

    private func save() {
        let delta: Decimal = difference
        guard delta != 0 else { return }
        let kind: TransactionKind = delta > 0 ? .income : .expense
        let adjustment = Transaction(
            amount: delta.magnitudeValue,
            kind: kind,
            title: "Balance adjustment",
            date: Date(),
            category: nil,
            account: account
        )
        context.insert(adjustment)
        try? context.save()
        dismiss()
    }
}

// MARK: - Editor

/// Create or edit an account.
struct AccountEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    let account: Account?

    @State private var name = ""
    @State private var kind: AccountKind = .checking
    @State private var symbol: String = AccountKind.checking.defaultSymbol
    /// Once the user picks an icon, changing the kind no longer replaces it.
    @State private var symbolChosen = false
    @State private var colorHex: String = Palette.swatches[3]
    @State private var opening: Decimal = 0
    @State private var openingNegative = false
    @State private var includeInNetWorth = true
    @State private var isDefault = false
    @State private var confirmArchive = false

    init(account: Account?) {
        self.account = account
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                balanceSection
                Section("Color") {
                    SwatchPicker(colorHex: $colorHex)
                        .padding(.vertical, 4)
                }
                Section("Icon") {
                    SymbolGridPicker(
                        symbol: Binding<String>(
                            get: { symbol },
                            set: { newValue in
                                symbol = newValue
                                symbolChosen = true
                            }
                        ),
                        colorHex: colorHex
                    )
                    .padding(.vertical, 4)
                }
                optionsSection
                if account != nil {
                    Section {
                        Button("Archive account", role: .destructive) { confirmArchive = true }
                    } footer: {
                        Text("Archived accounts are hidden and left out of net worth. Their transactions keep their history, and you can restore the account any time.")
                    }
                }
            }
            .tallyScreen()
            .navigationTitle(account == nil ? "New account" : "Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Archive this account?", isPresented: $confirmArchive, titleVisibility: .visible) {
                Button("Archive", role: .destructive, action: archive)
            }
            .onAppear(perform: load)
            .onChange(of: kind) { _, newKind in
                if !symbolChosen {
                    symbol = newKind.defaultSymbol
                }
                if account == nil && newKind == .credit && opening == 0 {
                    openingNegative = true
                }
            }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            HStack(spacing: 12) {
                CategoryIcon(symbol: symbol, colorHex: colorHex, size: 44)
                TextField("Account name", text: $name)
                    .font(.headlineSerif)
            }
            Picker("Type", selection: $kind) {
                ForEach(AccountKind.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        }
    }

    private var balanceSection: some View {
        Section {
            AmountField(title: "0", amount: $opening)
            Toggle("Negative balance (owed)", isOn: $openingNegative)
        } header: {
            Text("Opening balance")
        } footer: {
            Text(kind == .credit
                 ? "For a credit card, turn this on if you owe money today. Purchases will then grow the amount owed."
                 : "What the account held when you added it. Turn on the toggle if it starts below zero.")
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("Include in net worth", isOn: $includeInNetWorth)
            Toggle("Use as default account", isOn: $isDefault)
        } footer: {
            Text("The default account is preselected when you add a transaction.")
        }
    }

    // MARK: Actions

    private func load() {
        guard let account else {
            isDefault = settings.defaultAccountID == nil
            return
        }
        name = account.name
        kind = account.kind
        symbol = account.symbol
        symbolChosen = account.symbol != account.kind.defaultSymbol
        colorHex = account.colorHex
        opening = account.openingBalance.magnitudeValue
        openingNegative = account.openingBalance < 0
        includeInNetWorth = account.includeInNetWorth
        isDefault = settings.defaultAccountID == account.id
    }

    private func save() {
        let trimmed: String = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let target: Account
        if let account {
            target = account
        } else {
            let count: Int = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
            target = Account(name: trimmed, kind: kind, openingBalance: 0, colorHex: colorHex, sortOrder: count)
            context.insert(target)
        }
        target.name = trimmed
        target.kind = kind
        target.symbol = symbol
        target.colorHex = colorHex
        target.openingBalance = openingNegative ? -opening : opening
        target.includeInNetWorth = includeInNetWorth
        if isDefault {
            settings.defaultAccountID = target.id
        } else if settings.defaultAccountID == target.id {
            settings.defaultAccountID = nil
        }
        try? context.save()
        dismiss()
    }

    private func archive() {
        guard let account else { return }
        if settings.defaultAccountID == account.id {
            settings.defaultAccountID = nil
        }
        account.isArchived = true
        try? context.save()
        dismiss()
    }
}
