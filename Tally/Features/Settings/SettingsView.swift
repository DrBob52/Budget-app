import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import TallyCore

// MARK: - Settings

/// Preferences, security, reminders and data tools. Presented as a sheet from `RootView`.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(AppSettings.self) private var settings
    @Environment(AppLockController.self) private var lock
    @Environment(ProStore.self) private var store

    @State private var showPaywall = false
    @State private var confirmErase = false
    @State private var showNotificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                SettingsBudgetSection()
                SettingsCategoriesSection()
                SettingsSecuritySection()
                SettingsRemindersSection(showDenied: $showNotificationsDenied)
                SettingsAppearanceSection()
                dataSection
                proSection
                SettingsAboutSection()
                #if DEBUG
                debugSection
                #endif
            }
            .tallyScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .alert("Notifications are off", isPresented: $showNotificationsDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("Allow notifications for Tally in the system Settings to receive reminders.")
            }
            .confirmationDialog("Erase all data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { eraseAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every transaction, category, account, goal and shared budget on this device is deleted and settings return to their defaults. This cannot be undone.")
            }
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            SettingsExportRow()

            Button(role: .destructive) {
                confirmErase = true
            } label: {
                Label("Erase all data", systemImage: "trash")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Exports are plain CSV that opens in any spreadsheet.")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: Pro

    private var proSection: some View {
        Section {
            Button {
                showPaywall = true
            } label: {
                HStack {
                    Label("Tally Pro", systemImage: "sparkles")
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    proStatusText
                        .font(.subheadline)
                        .foregroundStyle(store.isPro ? Palette.accent : Palette.inkSecondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("Tally Pro")
        }
        .listRowBackground(Palette.surface)
    }

    private var proStatusText: Text {
        store.isPro ? Text("Active") : Text("Not unlocked")
    }

    // MARK: Debug

    #if DEBUG
    private var debugSection: some View {
        Section {
            Button("Load sample data") {
                SampleData.insert(into: context)
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Only in debug builds. Adds example categories, accounts and transactions.")
        }
        .listRowBackground(Palette.surface)
    }
    #endif

    // MARK: Erase

    @MainActor
    private func eraseAll() {
        // Children first, then parents. One call per concrete type in `TallySchema.models`.
        try? context.delete(model: SplitShare.self)
        try? context.delete(model: Settlement.self)
        try? context.delete(model: GoalContribution.self)
        try? context.delete(model: Transaction.self)
        try? context.delete(model: RecurringTemplate.self)
        try? context.delete(model: SavingsGoal.self)
        try? context.delete(model: Member.self)
        try? context.delete(model: Account.self)
        try? context.delete(model: Category.self)
        try? context.save()

        NotificationService.shared.cancelAll()
        settings.reset()
        lock.forceUnlock()
        dismiss()
    }
}

// MARK: - Small helpers

fileprivate extension View {
    /// Paper-colored row background used across the settings forms.
    func settingsRows() -> some View {
        self.listRowBackground(Palette.surface)
    }
}

// MARK: - Budget

private struct SettingsBudgetSection: View {
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    var body: some View {
        @Bindable var settings = settings
        Section {
            NavigationLink {
                SettingsCurrencyPicker()
            } label: {
                LabeledContent("Currency", value: "\(settings.currencyCode) · \(CurrencyCatalog.name(for: settings.currencyCode))")
            }

            Picker("Budget period", selection: $settings.periodKind) {
                ForEach(PeriodKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            startRow

            VStack(alignment: .leading, spacing: 4) {
                Text("Expected income per period")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                AmountField(title: "0", amount: $settings.monthlyIncome)
            }
            .padding(.vertical, 2)

            Toggle("Roll over unspent budget", isOn: $settings.rolloverEnabled)

            AccountPicker(title: "Default account", selection: defaultAccountBinding)
        } header: {
            Text("Budget")
        } footer: {
            Text("Rollover carries what you did not spend in a category into the next period, and carries overspending forward as a smaller allowance. Each category can opt in from its editor.")
        }
        .settingsRows()
    }

    @ViewBuilder
    private var startRow: some View {
        let bindable = Bindable(settings)
        switch settings.periodKind {
        case .monthly:
            Picker("Payday (period starts on day)", selection: bindable.monthlyStartDay) {
                ForEach(1...28, id: \.self) { day in
                    Text("Day \(day)").tag(day)
                }
            }
        case .weekly:
            Picker("Week starts on", selection: bindable.weeklyStartWeekday) {
                ForEach(1...7, id: \.self) { weekday in
                    Text(weekdayName(weekday)).tag(weekday)
                }
            }
        case .biweekly:
            DatePicker("A period starts on", selection: bindable.biweeklyAnchor, displayedComponents: .date)
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return String(localized: "Day \(weekday)") }
        return symbols[weekday - 1]
    }

    private var defaultAccountBinding: Binding<Account?> {
        Binding<Account?>(
            get: { accounts.first { $0.id == settings.defaultAccountID } },
            set: { settings.defaultAccountID = $0?.id }
        )
    }
}

// MARK: - Currency

/// Searchable list of every currency in `CurrencyCatalog`.
struct SettingsCurrencyPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var query = ""
    @State private var currencies: [CurrencyInfo] = CurrencyCatalog.all

    private var filtered: [CurrencyInfo] {
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return currencies }
        return currencies.filter {
            $0.name.localizedCaseInsensitiveContains(text) || $0.code.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { currency in
                Button {
                    settings.currencyCode = currency.code
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currency.name)
                                .foregroundStyle(Palette.ink)
                            Text(currency.code)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                        if currency.code == settings.currencyCode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(currency.code == settings.currencyCode ? .isSelected : [])
            }
            .settingsRows()
        }
        .tallyScreen()
        .searchable(text: $query, prompt: "Search currencies")
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Categories entry

private struct SettingsCategoriesSection: View {
    var body: some View {
        Section {
            NavigationLink {
                SettingsCategoriesView()
            } label: {
                Label("Categories", systemImage: "square.grid.2x2")
            }
        } header: {
            Text("Categories")
        } footer: {
            Text("Rename, reorder, recolor or archive the categories you budget with.")
        }
        .settingsRows()
    }
}

// MARK: - Security

private struct SettingsSecuritySection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppLockController.self) private var lock

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle(isOn: lockBinding) {
                Label("Lock with \(lock.biometryName)", systemImage: "lock")
            }
            .disabled(!lock.canAuthenticate && !settings.appLockEnabled)

            Toggle(isOn: $settings.hideAmounts) {
                Label("Hide amounts", systemImage: "eye.slash")
            }
        } header: {
            Text("Security & privacy")
        } footer: {
            Text("The lock appears whenever Tally opens or returns from the background. Hiding amounts blurs money on screen until you turn it off.")
        }
        .settingsRows()
    }

    private var lockBinding: Binding<Bool> {
        Binding<Bool>(
            get: { settings.appLockEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        let verified = await lock.verifyForEnabling()
                        if verified { settings.appLockEnabled = true }
                    }
                } else {
                    settings.appLockEnabled = false
                    lock.forceUnlock()
                }
            }
        )
    }
}

// MARK: - Reminders

private struct SettingsRemindersSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Binding var showDenied: Bool

    var body: some View {
        Section {
            Toggle(isOn: reminderBinding(\.dailyReminderEnabled)) {
                Label("Daily reminder", systemImage: "bell")
            }
            if settings.dailyReminderEnabled {
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
            Toggle(isOn: reminderBinding(\.billRemindersEnabled)) {
                Label("Bill reminders", systemImage: "calendar.badge.clock")
            }
            Toggle(isOn: reminderBinding(\.overspendAlertsEnabled)) {
                Label("Overspend alerts", systemImage: "exclamationmark.triangle")
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Bill reminders arrive the morning before a recurring bill is due. Overspend alerts appear once per period when a category reaches 90 percent of its budget.")
        }
        .settingsRows()
    }

    private func reminderBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding<Bool>(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                if newValue {
                    Task {
                        let granted = await NotificationService.shared.requestAuthorization()
                        settings[keyPath: keyPath] = granted
                        if !granted { showDenied = true }
                        reschedule()
                    }
                } else {
                    settings[keyPath: keyPath] = false
                    reschedule()
                }
            }
        )
    }

    private var reminderTime: Binding<Date> {
        Binding<Date>(
            get: {
                let minutes = settings.dailyReminderMinutes
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.dailyReminderMinutes = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
                reschedule()
            }
        )
    }

    @MainActor
    private func reschedule() {
        NotificationService.shared.reschedule(context: context, settings: settings)
    }
}

// MARK: - Appearance

private struct SettingsAppearanceSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        }
        .settingsRows()
    }
}

// MARK: - Export row

private struct SettingsExportRow: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Transaction.date) private var transactions: [Transaction]

    @State private var fileURL: URL?

    var body: some View {
        Group {
            if let fileURL, !transactions.isEmpty {
                ShareLink(item: fileURL) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            } else {
                Label("Export CSV", systemImage: "square.and.arrow.up")
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .task(id: transactions.count) {
            fileURL = ExportService.writeCSV(transactions: transactions, settings: settings)
        }
    }
}

// MARK: - About

private struct SettingsAboutSection: View {
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        Section {
            LabeledContent("Version", value: versionText)
            Label("Your data stays on this device.", systemImage: "hand.raised")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
        } header: {
            Text("About")
        } footer: {
            Text("Tally has no accounts and no tracking. Budgets and transactions are stored only on your device.")
        }
        .settingsRows()
    }
}

// MARK: - Categories screen

/// Reorder, edit, add, archive and restore categories.
struct SettingsCategoriesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var editing: Category?
    @State private var adding: CategoryKind?

    private var expense: [Category] {
        categories.filter { !$0.isArchived && $0.kind == .expense }
    }

    private var income: [Category] {
        categories.filter { !$0.isArchived && $0.kind == .income }
    }

    private var archived: [Category] {
        categories.filter { $0.isArchived }
    }

    var body: some View {
        List {
            categorySection(title: "Expense", addTitle: "Add expense category", kind: .expense, items: expense)
            categorySection(title: "Income", addTitle: "Add income category", kind: .income, items: income)
            if !archived.isEmpty {
                archivedSection
            }
        }
        .tallyScreen()
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(item: $editing) { category in
            CategoryEditorView(category: category)
        }
        .sheet(item: $adding) { kind in
            CategoryEditorView(category: nil, initialKind: kind)
        }
    }

    private func categorySection(title: LocalizedStringKey, addTitle: LocalizedStringKey, kind: CategoryKind, items: [Category]) -> some View {
        Section {
            ForEach(items) { category in
                Button {
                    editing = category
                } label: {
                    row(for: category)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        category.isArchived = true
                        try? context.save()
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(Palette.caution)
                }
            }
            .onMove { source, destination in
                move(items, from: source, to: destination)
            }

            Button {
                adding = kind
            } label: {
                Label(addTitle, systemImage: "plus.circle")
            }
        } header: {
            Text(title)
        }
        .settingsRows()
    }

    private func row(for category: Category) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category)
            Text(category.name)
                .foregroundStyle(Palette.ink)
            Spacer()
            if category.isBudgeted {
                Text(settings.format(category.budgetLimit, compact: true))
                    .font(.amountSmall)
                    .foregroundStyle(Palette.inkSecondary)
                    .hidesAmount(settings.hideAmounts)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.inkTertiary)
        }
        .contentShape(Rectangle())
    }

    private var archivedSection: some View {
        Section {
            DisclosureGroup("Archived (\(archived.count))") {
                ForEach(archived) { category in
                    HStack(spacing: 12) {
                        CategoryIcon(category: category)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.name)
                                .foregroundStyle(Palette.ink)
                            Text(category.kind.displayName)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                        Button("Restore") {
                            category.isArchived = false
                            try? context.save()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } footer: {
            Text("Archived categories keep their past transactions but no longer appear when adding new ones.")
        }
        .settingsRows()
    }

    /// Reorders one kind's list while keeping the sort slots it already occupied,
    /// so expense and income categories stay interleaved the way they were.
    private func move(_ list: [Category], from source: IndexSet, to destination: Int) {
        var items = list
        items.move(fromOffsets: source, toOffset: destination)
        let slots = list.map { $0.sortOrder }.sorted()
        let slotsAreUnique = Set(slots).count == slots.count
        for (index, category) in items.enumerated() {
            category.sortOrder = slotsAreUnique ? slots[index] : index
        }
        try? context.save()
    }
}

#Preview {
    SettingsView()
        .previewEnvironment()
}

#Preview("Categories") {
    NavigationStack {
        SettingsCategoriesView()
    }
    .previewEnvironment()
}
