import SwiftUI
import SwiftData
import TallyCore

// MARK: - Planning math

/// Deadline arithmetic for savings goals.
enum GoalPlan {
    /// Whole months left until the deadline, rounded up and never less than one.
    static func monthsRemaining(until deadline: Date, from now: Date = Date()) -> Int {
        let parts = Calendar.current.dateComponents([.month, .day], from: now, to: deadline)
        var months: Int = parts.month ?? 0
        if (parts.day ?? 0) > 0 { months += 1 }
        return max(months, 1)
    }

    static func isPastDeadline(_ deadline: Date, now: Date = Date()) -> Bool {
        deadline < Calendar.current.startOfDay(for: now)
    }

    /// Amount to put aside each month to finish by the deadline. Nil when there is nothing to plan.
    static func monthlyAmount(for goal: SavingsGoal, now: Date = Date()) -> Decimal? {
        guard !goal.isComplete, let deadline = goal.deadline, !isPastDeadline(deadline, now: now) else { return nil }
        let months = monthsRemaining(until: deadline, from: now)
        let perMonth: Decimal = goal.remainingAmount / Decimal(months)
        return perMonth.rounded(scale: 2, mode: .up)
    }

    /// "Save $120.00 per month to reach it by Mar 1, 2027", or a quiet note when the date has passed.
    static func deadlineLine(for goal: SavingsGoal, settings: AppSettings, now: Date = Date()) -> String? {
        guard !goal.isComplete, let deadline = goal.deadline else { return nil }
        let dateText: String = deadline.formatted(date: .abbreviated, time: .omitted)
        if isPastDeadline(deadline, now: now) {
            return "The target date, \(dateText), has passed."
        }
        guard let monthly = monthlyAmount(for: goal, now: now) else { return nil }
        return "Save \(settings.format(monthly)) per month to reach it by \(dateText)"
    }
}

// MARK: - Small pieces

/// Quiet "Done" badge for completed goals.
struct GoalDoneBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Done")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(Palette.accent)
        .background(Palette.accent.opacity(0.12), in: Capsule())
    }
}

/// Ring with the goal's icon in the middle, used on the card and in lists.
struct GoalRingIcon: View {
    let goal: SavingsGoal
    var size: CGFloat = 56
    var lineWidth: CGFloat = 6

    var body: some View {
        let tint: Color = goal.isComplete ? Palette.accent : Color(hex: goal.colorHex)
        ZStack {
            ProgressRing(progress: goal.progress, lineWidth: lineWidth, tint: tint)
            Image(systemName: goal.isComplete ? "checkmark" : goal.symbol)
                .font(.system(size: size * 0.3, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Card

/// A goal in the wallet list.
struct GoalCard: View {
    @Environment(AppSettings.self) private var settings

    let goal: SavingsGoal

    init(goal: SavingsGoal) {
        self.goal = goal
    }

    var body: some View {
        HStack(spacing: 14) {
            GoalRingIcon(goal: goal)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(goal.name)
                        .font(.headlineSerif)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if goal.isComplete {
                        GoalDoneBadge()
                    }
                }
                HStack(spacing: 4) {
                    MoneyText(amount: goal.savedAmount, font: Font.amountSmall)
                    Text("of")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                    MoneyText(amount: goal.targetAmount, font: Font.amountSmall)
                }
                if goal.isComplete {
                    Text("Goal reached")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    HStack(spacing: 4) {
                        MoneyText(amount: goal.remainingAmount, font: Font.caption)
                        Text("to go")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if let line = GoalPlan.deadlineLine(for: goal, settings: settings) {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .hidesAmount(settings.hideAmounts)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Detail

struct GoalDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    let goal: SavingsGoal

    @State private var contributionMode: GoalContributionMode?
    @State private var showEditor = false
    @State private var deleteRequested = false

    init(goal: SavingsGoal) {
        self.goal = goal
    }

    private var history: [GoalContribution] {
        (goal.contributions ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            historySection
        }
        .listStyle(.insetGrouped)
        .tallyScreen()
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .sheet(item: $contributionMode) { mode in
            GoalContributionView(goal: goal, mode: mode)
        }
        .sheet(isPresented: $showEditor, onDismiss: handleEditorDismiss) {
            GoalEditorView(goal: goal, onDelete: { deleteRequested = true })
        }
        .onChange(of: goal.isArchived) { _, archived in
            if archived { dismiss() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                ProgressRing(
                    progress: goal.progress,
                    lineWidth: 14,
                    tint: goal.isComplete ? Palette.accent : Color(hex: goal.colorHex)
                )
                ringCenter
            }
            .frame(width: 190, height: 190)
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(goal.name)
                    .font(.titleSerif)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                HStack(spacing: 4) {
                    MoneyText(amount: goal.savedAmount, font: Font.amount)
                    Text("of")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                    MoneyText(amount: goal.targetAmount, font: Font.amount)
                }
                if !goal.isComplete {
                    HStack(spacing: 4) {
                        MoneyText(amount: goal.remainingAmount, font: Font.subheadline)
                        Text("to go")
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                if let line = GoalPlan.deadlineLine(for: goal, settings: settings) {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .hidesAmount(settings.hideAmounts)
                } else if let deadline = goal.deadline, goal.isComplete {
                    Text("Target date \(deadline.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkTertiary)
                }
                if !goal.note.isEmpty {
                    Text(goal.note)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 8)

            if goal.isComplete {
                completedCard
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var ringCenter: some View {
        if goal.isComplete {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Palette.accent)
        } else {
            VStack(spacing: 2) {
                Text("\(Int((goal.progress * 100).rounded()))%")
                    .font(Font.display(40))
                    .foregroundStyle(Palette.ink)
                Text("saved")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private var completedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 22))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Goal reached")
                    .font(.headlineSerif)
                    .foregroundStyle(Palette.ink)
                Text("Everything you meant to set aside is here. It's yours to enjoy, or to withdraw whenever you're ready.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tallyCard()
        .padding(.horizontal, Metrics.screenPadding)
    }

    // MARK: History

    private var historySection: some View {
        let items: [GoalContribution] = history
        return Section {
            if items.isEmpty {
                Text("Nothing added yet. Use \u{201C}Add money\u{201D} to make your first deposit.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .listRowBackground(Palette.surface)
            } else {
                ForEach(items) { item in
                    GoalContributionRow(contribution: item, colorHex: goal.colorHex)
                        .listRowBackground(Palette.surface)
                        .listRowSeparatorTint(Palette.rule)
                }
                .onDelete(perform: deleteContributions)
            }
        } header: {
            SectionHeader("History")
                .textCase(nil)
        }
    }

    private func deleteContributions(at offsets: IndexSet) {
        let items: [GoalContribution] = history
        for index in offsets where index < items.count {
            context.delete(items[index])
        }
        try? context.save()
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                contributionMode = .add
            } label: {
                Label("Add money", systemImage: "plus")
            }
            .buttonStyle(.tallyPrimary)

            Button {
                contributionMode = .withdraw
            } label: {
                Label("Withdraw", systemImage: "arrow.down.left")
            }
            .buttonStyle(.tallySecondary)
            .disabled(goal.savedAmount <= 0)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Palette.paper)
    }

    /// Deleting waits until this screen has been popped, so nothing reads a removed goal.
    private func handleEditorDismiss() {
        guard deleteRequested else { return }
        deleteRequested = false
        let target: SavingsGoal = goal
        let modelContext: ModelContext = context
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            modelContext.delete(target)
            try? modelContext.save()
        }
    }
}

private struct GoalContributionRow: View {
    let contribution: GoalContribution
    let colorHex: String

    var body: some View {
        let isDeposit: Bool = contribution.amount >= 0
        HStack(spacing: 12) {
            CategoryIcon(symbol: isDeposit ? "arrow.down" : "arrow.up", colorHex: colorHex, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(isDeposit: isDeposit))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(contribution.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 8)
            MoneyText(amount: contribution.amount, showsSign: true, font: Font.amountSmall, colored: !isDeposit)
        }
        .padding(.vertical, 2)
    }

    private func title(isDeposit: Bool) -> String {
        if !contribution.note.isEmpty { return contribution.note }
        return isDeposit ? "Deposit" : "Withdrawal"
    }
}

// MARK: - Add / withdraw

enum GoalContributionMode: String, Identifiable {
    case add
    case withdraw

    var id: String { rawValue }
}

/// Sheet for adding money to a goal or taking some back out.
struct GoalContributionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    let goal: SavingsGoal
    let mode: GoalContributionMode

    @State private var amount: Decimal = 0
    @State private var note = ""
    @State private var date = Date()

    init(goal: SavingsGoal, mode: GoalContributionMode) {
        self.goal = goal
        self.mode = mode
    }

    private var isWithdrawal: Bool { mode == .withdraw }

    private var isValid: Bool {
        guard amount > 0 else { return false }
        if isWithdrawal { return amount <= goal.savedAmount }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "0", amount: $amount, large: true)
                } footer: {
                    if isWithdrawal {
                        Text("You can take out up to \(settings.format(goal.savedAmount)).")
                            .hidesAmount(settings.hideAmounts)
                    } else if goal.remainingAmount > 0 {
                        Text("\(settings.format(goal.remainingAmount)) to go.")
                            .hidesAmount(settings.hideAmounts)
                    }
                }
                Section {
                    TextField("Note (optional)", text: $note)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .tallyScreen()
            .navigationTitle(isWithdrawal ? "Withdraw" : "Add money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard isValid else { return }
        let signed: Decimal = isWithdrawal ? -amount : amount
        let trimmedNote: String = note.trimmingCharacters(in: .whitespaces)
        let contribution = GoalContribution(amount: signed, date: date, note: trimmedNote)
        contribution.goal = goal
        context.insert(contribution)
        try? context.save()
        dismiss()
    }
}

// MARK: - Editor

/// Create or edit a savings goal.
struct GoalEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let goal: SavingsGoal?
    let onDelete: (() -> Void)?

    @State private var name = ""
    @State private var target: Decimal = 0
    @State private var hasDeadline = false
    @State private var deadline: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var colorHex: String = Palette.swatches[9]
    @State private var symbol = "star"
    @State private var note = ""
    @State private var confirmArchive = false
    @State private var confirmDelete = false

    init(goal: SavingsGoal?, onDelete: (() -> Void)? = nil) {
        self.goal = goal
        self.onDelete = onDelete
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && target > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CategoryIcon(symbol: symbol, colorHex: colorHex, size: 44)
                        TextField("Goal name", text: $name)
                            .font(.headlineSerif)
                    }
                }
                Section("Target") {
                    AmountField(title: "0", amount: $target)
                }
                Section {
                    Toggle("Target date", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("Reach it by", selection: $deadline, displayedComponents: .date)
                    }
                } footer: {
                    Text("With a date, Tally works out how much to set aside each month.")
                }
                Section("Color") {
                    SwatchPicker(colorHex: $colorHex)
                        .padding(.vertical, 4)
                }
                Section("Icon") {
                    SymbolGridPicker(symbol: $symbol, colorHex: colorHex)
                        .padding(.vertical, 4)
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                if goal != nil {
                    Section {
                        Button("Archive goal") { confirmArchive = true }
                        Button("Delete goal", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Archiving hides the goal and keeps its history. Deleting removes it and every deposit.")
                    }
                }
            }
            .tallyScreen()
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
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
            .confirmationDialog("Archive this goal?", isPresented: $confirmArchive, titleVisibility: .visible) {
                Button("Archive", action: archive)
            }
            .confirmationDialog("Delete this goal?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete goal and history", role: .destructive, action: delete)
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let goal else { return }
        name = goal.name
        target = goal.targetAmount
        if let existing = goal.deadline {
            hasDeadline = true
            deadline = existing
        }
        colorHex = goal.colorHex
        symbol = goal.symbol
        note = goal.note
    }

    private func save() {
        let trimmed: String = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, target > 0 else { return }
        let resolvedDeadline: Date? = hasDeadline ? deadline : nil
        let saved: SavingsGoal
        if let goal {
            saved = goal
        } else {
            let count: Int = (try? context.fetchCount(FetchDescriptor<SavingsGoal>())) ?? 0
            saved = SavingsGoal(name: trimmed, targetAmount: target, symbol: symbol, colorHex: colorHex, deadline: resolvedDeadline)
            saved.sortOrder = count
            context.insert(saved)
        }
        saved.name = trimmed
        saved.targetAmount = target
        saved.symbol = symbol
        saved.colorHex = colorHex
        saved.deadline = resolvedDeadline
        saved.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        dismiss()
    }

    private func archive() {
        guard let goal else { return }
        goal.isArchived = true
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let goal else { return }
        if let onDelete {
            onDelete()
        } else {
            context.delete(goal)
            try? context.save()
        }
        dismiss()
    }
}
