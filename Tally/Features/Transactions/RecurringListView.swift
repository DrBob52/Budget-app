import SwiftUI
import SwiftData
import TallyCore

/// What the recurring editor sheet is opened for.
enum RecurringEditorTarget: Identifiable {
    case new
    case edit(RecurringTemplate)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let template): return template.id.uuidString
        }
    }

    var template: RecurringTemplate? {
        switch self {
        case .new: return nil
        case .edit(let template): return template
        }
    }
}

/// A template paired with its next due date, computed once per render.
private struct RecurringListItem: Identifiable {
    let template: RecurringTemplate
    let next: Date?
    var id: UUID { template.id }
}

// MARK: - List

struct RecurringListView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \RecurringTemplate.title) private var templates: [RecurringTemplate]
    @State private var target: RecurringEditorTarget?

    var body: some View {
        let items: [RecurringListItem] = templates.map { RecurringListItem(template: $0, next: $0.nextDueDate) }
        let active: [RecurringListItem] = sortedByDue(items.filter { $0.template.isActive })
        let paused: [RecurringListItem] = items.filter { !$0.template.isActive }
        let monthly: Decimal = RecurringMath.monthlyExpenseTotal(of: templates)

        Group {
            if templates.isEmpty {
                emptyState
            } else {
                list(active: active, paused: paused, monthly: monthly)
            }
        }
        .tallyScreen()
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    target = .new
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add recurring item")
            }
        }
        .sheet(item: $target) { item in
            RecurringEditorView(template: item.template)
        }
    }

    private func sortedByDue(_ items: [RecurringListItem]) -> [RecurringListItem] {
        items.sorted { lhs, rhs in
            switch (lhs.next, rhs.next) {
            case let (a?, b?):
                return a < b
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.template.title.localizedCaseInsensitiveCompare(rhs.template.title) == .orderedAscending
            }
        }
    }

    private func list(active: [RecurringListItem], paused: [RecurringListItem], monthly: Decimal) -> some View {
        List {
            Section {
                summaryCard(monthly: monthly)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if !active.isEmpty {
                Section {
                    ForEach(active) { item in
                        row(item)
                    }
                } header: {
                    Overline("Active")
                }
            }
            if !paused.isEmpty {
                Section {
                    ForEach(paused) { item in
                        row(item)
                    }
                } header: {
                    Overline("Paused")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func summaryCard(monthly: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Overline("Your repeating costs")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\u{2248}")
                    .font(.display(24, weight: .regular))
                    .foregroundStyle(Palette.inkSecondary)
                MoneyText(amount: monthly, font: .display(34))
                Text("/ month")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Text("Active bills and subscriptions, averaged over a month.")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
        .tallyCard()
    }

    private func row(_ item: RecurringListItem) -> some View {
        let template = item.template
        return Button {
            target = .edit(template)
        } label: {
            RecurringRow(template: template, next: item.next)
        }
        .buttonStyle(.plain)
        .listRowBackground(Palette.surface)
        .listRowSeparatorTint(Palette.rule)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                context.delete(template)
                try? context.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                template.isActive.toggle()
                try? context.save()
            } label: {
                if template.isActive {
                    Label("Pause", systemImage: "pause")
                } else {
                    Label("Resume", systemImage: "play")
                }
            }
            .tint(Palette.caution)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(
                symbol: "repeat",
                title: "Nothing repeats yet",
                message: "Add rent, subscriptions or a paycheck and Tally will log each one when it comes due.",
                actionTitle: "Add a recurring item",
                action: { target = .new }
            )
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Row

struct RecurringRow: View {
    let template: RecurringTemplate
    let next: Date?

    var body: some View {
        HStack(spacing: 12) {
            if let category = template.category {
                CategoryIcon(category: category)
            } else {
                CategoryIcon(symbol: "repeat", colorHex: "#4A5560")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(template.title.isEmpty ? template.kind.displayName : template.title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if template.kind == .income {
                MoneyText(amount: template.amount, showsSign: true, colored: true)
            } else {
                MoneyText(amount: template.amount)
            }
        }
        .padding(.vertical, 2)
        .opacity(template.isActive ? 1 : 0.55)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let frequency = template.frequency.displayName
        if !template.isActive { return String(localized: "\(frequency) \u{00B7} Paused") }
        guard let next else { return String(localized: "\(frequency) \u{00B7} Ended") }
        let when = next.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "\(frequency) \u{00B7} Next \(when)")
    }
}

// MARK: - Editor

struct RecurringEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    let template: RecurringTemplate?

    @State private var kind: TransactionKind
    @State private var title: String
    @State private var amount: Decimal
    @State private var category: Category?
    @State private var account: Account?
    @State private var frequency: RecurrenceFrequency
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var isActive: Bool
    @State private var remind: Bool
    @State private var confirmDelete = false
    @State private var didDelete = false
    @State private var didSetDefaults = false

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    init(template: RecurringTemplate? = nil) {
        self.template = template
        _kind = State(initialValue: template?.kind == .income ? .income : .expense)
        _title = State(initialValue: template?.title ?? "")
        _amount = State(initialValue: template?.amount ?? 0)
        _category = State(initialValue: template?.category)
        _account = State(initialValue: template?.account)
        _frequency = State(initialValue: template?.frequency ?? .monthly)
        let start: Date = template?.startDate ?? Date()
        _startDate = State(initialValue: start)
        _hasEndDate = State(initialValue: template?.endDate != nil)
        let fallbackEnd: Date = Calendar.current.date(byAdding: .year, value: 1, to: start) ?? start
        _endDate = State(initialValue: template?.endDate ?? fallbackEnd)
        _isActive = State(initialValue: template?.isActive ?? true)
        _remind = State(initialValue: template?.remindBeforeDue ?? false)
    }

    private var categoryKind: CategoryKind { kind == .income ? .income : .expense }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { amount > 0 && !trimmedTitle.isEmpty }

    var body: some View {
        if didDelete {
            Color.clear
        } else {
            editorBody
        }
    }

    private var editorBody: some View {
        NavigationStack {
            Form {
                basicsSection
                categorySection
                scheduleSection
                optionsSection
                if template != nil {
                    Section {
                        Button("Delete recurring item", role: .destructive) {
                            confirmDelete = true
                        }
                    } footer: {
                        Text("Entries already added to your ledger stay where they are.")
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .tallyScreen()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(template == nil ? Text("New recurring item") : Text("Edit recurring item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this recurring item?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteTemplate)
            }
            .onAppear(perform: applyDefaults)
            .onChange(of: kind) { _, newKind in
                if let current = category {
                    let wanted: CategoryKind = newKind == .income ? .income : .expense
                    if current.kind != wanted { category = nil }
                }
            }
        }
    }

    private var basicsSection: some View {
        Section {
            Picker("Type", selection: $kind) {
                Text(TransactionKind.expense.displayName).tag(TransactionKind.expense)
                Text(TransactionKind.income.displayName).tag(TransactionKind.income)
            }
            .pickerStyle(.segmented)
            AmountField(title: "0", amount: $amount, large: true)
                .padding(.vertical, 4)
            TextField("Name, such as Rent or Streaming", text: $title)
                .textInputAutocapitalization(.words)
            AccountPicker(title: "Account", selection: $account)
        } header: {
            Overline("Basics")
        }
        .listRowBackground(Palette.surface)
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

    private var scheduleSection: some View {
        Section {
            Picker("Frequency", selection: $frequency) {
                ForEach(RecurrenceFrequency.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            DatePicker("Starts", selection: $startDate, displayedComponents: .date)
            Toggle("Stop on a date", isOn: $hasEndDate)
            if hasEndDate {
                DatePicker("Last one on", selection: $endDate, in: startDate..., displayedComponents: .date)
            }
        } header: {
            Overline("Schedule")
        } footer: {
            Text("Entries are added automatically when they come due. A start date in the past adds the ones you missed.")
        }
        .listRowBackground(Palette.surface)
    }

    private var optionsSection: some View {
        Section {
            Toggle("Active", isOn: $isActive)
            Toggle("Remind me before it's due", isOn: $remind)
        } header: {
            Overline("Options")
        }
        .listRowBackground(Palette.surface)
    }

    private func applyDefaults() {
        if didSetDefaults { return }
        didSetDefaults = true
        if template == nil, account == nil, let defaultID = settings.defaultAccountID {
            account = accounts.first(where: { $0.id == defaultID })
        }
    }

    private func save() {
        guard canSave else { return }
        let target: RecurringTemplate
        if let existing = template {
            target = existing
        } else {
            target = RecurringTemplate(
                title: trimmedTitle,
                amount: amount,
                kind: kind,
                frequency: frequency,
                startDate: startDate,
                category: category,
                account: account
            )
            // Nothing is logged until it comes due; the start date itself is the first occurrence.
            target.lastGeneratedDate = nil
            context.insert(target)
        }
        target.title = trimmedTitle
        target.amount = amount
        target.kind = kind
        target.category = category
        target.account = account
        target.frequency = frequency
        target.startDate = startDate
        target.endDate = hasEndDate ? endDate : nil
        target.isActive = isActive
        target.remindBeforeDue = remind
        try? context.save()

        // A start date that is already due should show up right away.
        RecurringService.generateDueTransactions(in: context)
        dismiss()
    }

    private func deleteTemplate() {
        guard let template else { return }
        didDelete = true
        context.delete(template)
        try? context.save()
        dismiss()
    }
}

#Preview("Recurring list") {
    NavigationStack {
        RecurringListView()
    }
    .previewEnvironment()
}

#Preview("Recurring editor") {
    RecurringEditorView()
        .previewEnvironment()
}
