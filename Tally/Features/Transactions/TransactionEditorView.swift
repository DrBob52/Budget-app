import SwiftUI
import SwiftData
import UIKit
import TallyCore

/// Small decimal text field used for per-person split inputs.
struct LedgerDecimalField: View {
    let placeholder: String
    @Binding var value: Decimal
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.amountSmall)
            .foregroundStyle(Palette.ink)
            .onAppear {
                text = value == 0 ? "" : AmountField.editingString(value)
            }
            .onChange(of: text) { _, newValue in
                value = AmountField.parse(newValue) ?? 0
            }
    }
}

/// Add or edit a transaction. Presented as a sheet with its own navigation stack.
struct TransactionEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    let transaction: Transaction?
    var initialKind: TransactionKind = .expense

    @Query(sort: \Member.createdAt) private var members: [Member]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]
    @Query private var recent: [Transaction]

    // Core fields
    @State private var kind: TransactionKind = .expense
    @State private var amount: Decimal = 0
    @State private var title = ""
    @State private var category: Category?
    @State private var account: Account?
    @State private var toAccount: Account?
    @State private var date = Date()
    @State private var note = ""

    // Repeat
    @State private var repeats = false
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var remind = false
    @State private var keepRepeating = true

    // Split
    @State private var splitOn = false
    @State private var paidBy: Member?
    @State private var splitMethod: SplitMethod = .equal
    @State private var included: Set<UUID> = []
    @State private var inputs: [UUID: Decimal] = [:]

    // UI
    @State private var confirmDelete = false
    @State private var saveTick = 0
    @State private var isSaving = false
    @State private var didSetDefaults = false
    @FocusState private var titleFocused: Bool

    init(transaction: Transaction? = nil, initialKind: TransactionKind = .expense) {
        self.transaction = transaction
        self.initialKind = initialKind

        var descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
        )
        descriptor.fetchLimit = 400
        _recent = Query(descriptor)

        let startKind: TransactionKind = transaction?.kind ?? initialKind
        _kind = State(initialValue: startKind)

        if let transaction {
            _amount = State(initialValue: transaction.amount)
            _title = State(initialValue: transaction.title)
            _category = State(initialValue: transaction.category)
            _account = State(initialValue: transaction.account)
            _toAccount = State(initialValue: transaction.toAccount)
            _date = State(initialValue: transaction.date)
            _note = State(initialValue: transaction.note)

            if let template = transaction.recurringTemplate {
                _keepRepeating = State(initialValue: template.isActive)
            }

            let shares: [SplitShare] = transaction.splitShares ?? []
            if !shares.isEmpty {
                let method: SplitMethod = transaction.splitMethod
                var loadedIncluded: Set<UUID> = []
                var loadedInputs: [UUID: Decimal] = [:]
                for share in shares {
                    guard let memberID = share.member?.id else { continue }
                    loadedIncluded.insert(memberID)
                    loadedInputs[memberID] = (method == .exact) ? share.amount : share.weight
                }
                _splitOn = State(initialValue: true)
                _paidBy = State(initialValue: transaction.paidBy)
                _splitMethod = State(initialValue: method)
                _included = State(initialValue: loadedIncluded)
                _inputs = State(initialValue: loadedInputs)
            }
        }
    }

    // MARK: Derived values

    private var categoryKind: CategoryKind { kind == .income ? .income : .expense }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isTransfer: Bool { kind == .transfer }
    private var showsSplit: Bool { kind == .expense && members.count >= 2 }
    private var includedMembers: [Member] { members.filter { included.contains($0.id) } }

    private var canSave: Bool {
        if isSaving { return false }
        if amount <= 0 { return false }
        if isTransfer {
            guard let from = account, let to = toAccount else { return false }
            if from.id == to.id { return false }
        }
        if splitProblem != nil { return false }
        return true
    }

    private var screenTitle: String {
        let name = kind.displayName.lowercased()
        return transaction == nil ? "New \(name)" : "Edit \(name)"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                amountSection
                detailsSection
                if !isTransfer {
                    categorySection
                }
                accountSection
                noteSection
                repeatSection
                if showsSplit {
                    splitSection
                }
                if transaction != nil {
                    deleteSection
                }
            }
            .tallyScreen()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { endEditing() }
                }
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteTransaction)
            }
            .sensoryFeedback(.success, trigger: saveTick)
            .onAppear(perform: applyDefaults)
            .onChange(of: kind) { _, newKind in
                handleKindChange(newKind)
            }
            .onChange(of: splitOn) { _, isOn in
                if isOn { prepareSplit() }
            }
            .onChange(of: splitMethod) { _, _ in
                resetInputs()
            }
        }
    }

    // MARK: Sections

    private var kindSection: some View {
        Section {
            Picker("Type", selection: $kind) {
                ForEach(TransactionKind.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private var amountSection: some View {
        Section {
            AmountField(title: "0", amount: $amount, large: true)
                .padding(.vertical, 6)
        }
        .listRowBackground(Palette.surface)
    }

    private var detailsSection: some View {
        Section {
            TextField(isTransfer ? "Title (optional)" : "Payee or title", text: $title)
                .focused($titleFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
            let options: [Transaction] = suggestions
            if !options.isEmpty {
                suggestionRow(options)
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
        } header: {
            Overline("Details")
        }
        .listRowBackground(Palette.surface)
    }

    private func suggestionRow(_ options: [Transaction]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    Button {
                        applySuggestion(option)
                    } label: {
                        HStack(spacing: 6) {
                            CategoryIcon(category: option.category, size: 22)
                            Text(option.title)
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                        .padding(.leading, 4)
                        .padding(.trailing, 10)
                        .background(Palette.sunken, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categorySection: some View {
        Section {
            CategoryPicker(selection: $category, kind: categoryKind)
                .padding(.vertical, 4)
        } header: {
            Overline("Category")
        }
        .listRowBackground(Palette.surface)
    }

    private var accountSection: some View {
        Section {
            if isTransfer {
                AccountPicker(title: "From", selection: $account, excluding: toAccount)
                AccountPicker(title: "To", selection: $toAccount, excluding: account)
            } else {
                AccountPicker(title: "Account", selection: $account)
            }
        } header: {
            Overline(isTransfer ? "Move money" : "Account")
        }
        .listRowBackground(Palette.surface)
    }

    private var noteSection: some View {
        Section {
            TextField("Note", text: $note, axis: .vertical)
                .lineLimit(1...4)
        } header: {
            Overline("Note")
        }
        .listRowBackground(Palette.surface)
    }

    @ViewBuilder
    private var repeatSection: some View {
        Section {
            if let template = transaction?.recurringTemplate {
                LabeledContent("Repeats", value: template.frequency.displayName)
                if let next = template.nextDueDate, keepRepeating {
                    LabeledContent("Next one", value: next.formatted(date: .abbreviated, time: .omitted))
                }
                Toggle("Keep repeating", isOn: $keepRepeating)
            } else {
                Toggle("Repeat", isOn: $repeats)
                if repeats {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Toggle("Stop on a date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Last one on", selection: $endDate, in: date..., displayedComponents: .date)
                    }
                    Toggle("Remind me before it's due", isOn: $remind)
                }
            }
        } header: {
            Overline("Repeat")
        } footer: {
            if transaction?.recurringTemplate == nil && repeats {
                Text("Future entries are added automatically when they come due.")
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var splitSection: some View {
        Section {
            Toggle("Split with others", isOn: $splitOn)
            if splitOn {
                MemberPicker(title: "Paid by", selection: $paidBy)
                Picker("Method", selection: $splitMethod) {
                    ForEach(SplitMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                ForEach(members) { member in
                    memberRow(member)
                        .id("\(member.id.uuidString)-\(splitMethod.rawValue)")
                }
            }
        } header: {
            Overline("Split")
        } footer: {
            if let problem = splitProblem {
                Text(problem)
                    .foregroundStyle(Palette.negative)
            } else if splitOn && splitMethod == .percentage {
                Text("Percentages that don't add up to 100 are scaled to fit.")
            } else if splitOn && splitMethod == .shares {
                Text("A person with 2 shares owes twice as much as a person with 1.")
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var deleteSection: some View {
        Section {
            Button("Delete transaction", role: .destructive) {
                confirmDelete = true
            }
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: Split rows

    private func memberRow(_ member: Member) -> some View {
        let isIncluded = included.contains(member.id)
        let shares: [UUID: Decimal] = isIncluded ? computeShares() : [:]
        let share: Decimal = shares[member.id] ?? 0
        return HStack(spacing: 10) {
            Button {
                toggleMember(member)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isIncluded ? Palette.accent : Palette.inkTertiary)
                    MemberAvatar(member: member, size: 28)
                    Text(member.isMe ? "\(member.name) (you)" : member.name)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            if isIncluded {
                memberTrailing(member, share: share)
            }
        }
    }

    @ViewBuilder
    private func memberTrailing(_ member: Member, share: Decimal) -> some View {
        switch splitMethod {
        case .equal:
            MoneyText(amount: share, font: .amountSmall)
        case .exact:
            LedgerDecimalField(placeholder: "0", value: inputBinding(for: member.id))
                .frame(width: 90)
        case .percentage:
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
                    LedgerDecimalField(placeholder: "0", value: inputBinding(for: member.id))
                        .frame(width: 60)
                    Text("%")
                        .font(.amountSmall)
                        .foregroundStyle(Palette.inkSecondary)
                }
                MoneyText(amount: share, font: .caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        case .shares:
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
                    LedgerDecimalField(placeholder: "0", value: inputBinding(for: member.id))
                        .frame(width: 60)
                    Text("\u{00D7}")
                        .font(.amountSmall)
                        .foregroundStyle(Palette.inkSecondary)
                }
                MoneyText(amount: share, font: .caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func inputBinding(for id: UUID) -> Binding<Decimal> {
        Binding<Decimal>(
            get: { inputs[id] ?? 0 },
            set: { inputs[id] = $0 }
        )
    }

    // MARK: Split logic

    private func weights(for ids: [UUID]) -> [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for id in ids {
            result[id] = inputs[id] ?? 0
        }
        return result
    }

    /// Amount each included member owes, by member id.
    private func computeShares() -> [UUID: Decimal] {
        let ids: [UUID] = includedMembers.map { $0.id }
        if ids.isEmpty { return [:] }
        switch splitMethod {
        case .equal:
            return SplitCalculator.equalShares(amount: amount, among: ids)
        case .exact:
            return weights(for: ids)
        case .percentage:
            return SplitCalculator.percentageShares(amount: amount, percentages: weights(for: ids), order: ids)
        case .shares:
            return SplitCalculator.weightedShares(amount: amount, weights: weights(for: ids), order: ids)
        }
    }

    /// Explains why the split can't be saved, or nil when it's fine (or off).
    private var splitProblem: String? {
        guard showsSplit, splitOn else { return nil }
        if includedMembers.isEmpty {
            return "Choose at least one person to share this with."
        }
        if splitMethod == .exact {
            var sum: Decimal = 0
            for member in includedMembers {
                sum += inputs[member.id] ?? 0
            }
            let difference: Decimal = (amount - sum).rounded(scale: 2)
            if difference > 0 {
                return "\(settings.format(difference)) still to assign."
            }
            if difference < 0 {
                return "\(settings.format(-difference)) over the total."
            }
            return nil
        }
        if computeShares().isEmpty {
            return "Enter a value for at least one person."
        }
        return nil
    }

    private func toggleMember(_ member: Member) {
        if included.contains(member.id) {
            included.remove(member.id)
        } else {
            included.insert(member.id)
            if inputs[member.id] == nil {
                inputs[member.id] = (splitMethod == .shares) ? 1 : 0
            }
        }
    }

    /// Fresh starting values for the per-person inputs of the current method.
    private func resetInputs() {
        let ids: [UUID] = includedMembers.map { $0.id }
        var fresh: [UUID: Decimal] = [:]
        switch splitMethod {
        case .equal:
            break
        case .exact:
            fresh = SplitCalculator.equalShares(amount: amount, among: ids)
        case .percentage:
            if !ids.isEmpty {
                let each: Decimal = (Decimal(100) / Decimal(ids.count)).rounded(scale: 2)
                for id in ids { fresh[id] = each }
            }
        case .shares:
            for id in ids { fresh[id] = 1 }
        }
        inputs = fresh
    }

    private func prepareSplit() {
        if paidBy == nil {
            paidBy = members.first(where: { $0.isMe }) ?? members.first
        }
        if included.isEmpty {
            included = Set(members.map { $0.id })
            resetInputs()
        }
    }

    // MARK: Suggestions

    private var suggestions: [Transaction] {
        guard titleFocused else { return [] }
        let needle = trimmedTitle.lowercased()
        var seen: Set<String> = []
        var result: [Transaction] = []
        for candidate in recent {
            if candidate.kind != kind { continue }
            let name = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            let lower = name.lowercased()
            if !needle.isEmpty {
                if lower == needle || !lower.contains(needle) { continue }
            }
            if seen.contains(lower) { continue }
            seen.insert(lower)
            result.append(candidate)
            if result.count >= 5 { break }
        }
        return result
    }

    private func applySuggestion(_ suggestion: Transaction) {
        title = suggestion.title
        if kind != .transfer, let suggested = suggestion.category, suggested.kind == categoryKind, !suggested.isArchived {
            category = suggested
        }
        titleFocused = false
    }

    // MARK: Lifecycle

    private func applyDefaults() {
        if didSetDefaults { return }
        didSetDefaults = true
        if transaction == nil, account == nil, let defaultID = settings.defaultAccountID {
            account = accounts.first(where: { $0.id == defaultID })
        }
        if paidBy == nil {
            paidBy = members.first(where: { $0.isMe }) ?? members.first
        }
        if endDate <= date {
            endDate = Calendar.current.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }

    private func handleKindChange(_ newKind: TransactionKind) {
        if newKind == .transfer {
            category = nil
            if toAccount?.id == account?.id { toAccount = nil }
        } else if let current = category {
            let wanted: CategoryKind = newKind == .income ? .income : .expense
            if current.kind != wanted { category = nil }
        }
        if newKind != .expense {
            splitOn = false
        }
        if newKind != .transfer {
            toAccount = nil
        }
    }

    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: Save and delete

    private func save() {
        guard canSave else { return }
        isSaving = true

        let target: Transaction
        if let existing = transaction {
            target = existing
        } else {
            target = Transaction(amount: amount, kind: kind)
            context.insert(target)
        }

        target.amount = amount
        target.kind = kind
        target.title = trimmedTitle
        target.date = date
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.category = isTransfer ? nil : category
        target.account = account
        target.toAccount = isTransfer ? toAccount : nil

        applyRepeat(to: target)
        applySplit(to: target)

        try? context.save()
        saveTick += 1

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            dismiss()
        }
    }

    private func applyRepeat(to target: Transaction) {
        if let template = target.recurringTemplate {
            template.isActive = keepRepeating
        } else if repeats {
            let template = RecurringTemplate(
                title: target.displayTitle,
                amount: amount,
                kind: kind,
                frequency: frequency,
                startDate: date,
                category: target.category,
                account: target.account
            )
            template.note = target.note
            template.endDate = hasEndDate ? endDate : nil
            template.lastGeneratedDate = date
            template.remindBeforeDue = remind
            context.insert(template)
            target.recurringTemplate = template
        }
    }

    private func applySplit(to target: Transaction) {
        let existingShares: [SplitShare] = target.splitShares ?? []

        // Only expenses can be split.
        if kind != .expense {
            for share in existingShares { context.delete(share) }
            target.paidBy = nil
            target.splitMethod = .equal
            return
        }
        // The section is hidden without at least two members; leave any data alone.
        if !showsSplit { return }

        for share in existingShares { context.delete(share) }

        if !splitOn {
            target.paidBy = nil
            target.splitMethod = .equal
            return
        }

        target.paidBy = paidBy ?? members.first(where: { $0.isMe })
        target.splitMethod = splitMethod

        let shares: [UUID: Decimal] = computeShares()
        for member in includedMembers {
            let owed: Decimal = shares[member.id] ?? 0
            if owed <= 0 { continue }
            let weight: Decimal
            switch splitMethod {
            case .equal: weight = 1
            case .exact: weight = owed
            case .percentage, .shares: weight = inputs[member.id] ?? 0
            }
            let share = SplitShare(amount: owed, weight: weight, member: member)
            context.insert(share)
            share.transaction = target
        }
    }

    private func deleteTransaction() {
        guard let transaction else { return }
        context.delete(transaction)
        try? context.save()
        saveTick += 1
        dismiss()
    }
}

#Preview("New expense") {
    TransactionEditorView()
        .previewEnvironment()
}

#Preview("New income") {
    TransactionEditorView(initialKind: .income)
        .previewEnvironment()
}
