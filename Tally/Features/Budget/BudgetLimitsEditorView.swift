import SwiftUI
import SwiftData
import TallyCore

/// Edit every expense category's limit (and rollover flag) in one place. Changes apply on Done.
struct BudgetLimitsEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    @State private var limitDrafts: [UUID: Decimal] = [:]
    @State private var rollDrafts: [UUID: Bool] = [:]
    @State private var showingNewCategory = false

    init() {}

    private var categories: [Category] {
        allCategories.filter { !$0.isArchived && $0.kind == .expense }
    }

    private func limit(for category: Category) -> Decimal {
        limitDrafts[category.id] ?? category.budgetLimit
    }

    private func rolls(for category: Category) -> Bool {
        rollDrafts[category.id] ?? category.rollsOver
    }

    private var totalBudgeted: Decimal {
        categories.reduce(Decimal(0)) { $0 + limit(for: $1) }
    }

    var body: some View {
        NavigationStack {
            Form {
                totalsSection
                categoriesSection
                addSection
            }
            .tallyScreen()
            .navigationTitle("Edit budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                }
            }
            .sheet(isPresented: $showingNewCategory) {
                CategoryEditorView(category: nil)
            }
        }
    }

    // MARK: Sections

    private var totalsSection: some View {
        let total: Decimal = totalBudgeted
        let income: Decimal = settings.monthlyIncome
        let unassigned: Decimal = income - total
        return Section {
            HStack {
                Text("Budgeted")
                    .foregroundStyle(Palette.ink)
                Spacer()
                MoneyText(amount: total, font: .amount)
            }
            .listRowBackground(Palette.surface)
            .accessibilityElement(children: .combine)

            if income > 0 {
                HStack {
                    Text("Expected income")
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    MoneyText(amount: income, font: .amount)
                }
                .listRowBackground(Palette.surface)
                .accessibilityElement(children: .combine)

                HStack {
                    Text(unassigned < 0 ? "Over-assigned" : "Unassigned")
                        .foregroundStyle(unassigned < 0 ? Palette.negative : Palette.ink)
                    Spacer()
                    BudgetAmountLabel(
                        amount: unassigned.magnitudeValue,
                        font: .amount,
                        color: unassigned < 0 ? Palette.negative : Palette.accent
                    )
                }
                .listRowBackground(Palette.surface)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Overview")
        } footer: {
            if income > 0 {
                Text("Unassigned is expected income minus everything you have set aside below.")
            }
        }
    }

    private var categoriesSection: some View {
        Section {
            if categories.isEmpty {
                Text("No expense categories yet.")
                    .foregroundStyle(Palette.inkSecondary)
                    .listRowBackground(Palette.surface)
            }
            ForEach(categories) { category in
                BudgetLimitRow(
                    category: category,
                    limit: limitBinding(for: category),
                    rollsOver: rollBinding(for: category),
                    rolloverEnabled: settings.rolloverEnabled
                )
                .listRowBackground(Palette.surface)
            }
        } header: {
            Text("Limits per period")
        } footer: {
            Text(rolloverFooter)
        }
    }

    private var addSection: some View {
        Section {
            Button {
                showingNewCategory = true
            } label: {
                Label("Add category", systemImage: "plus")
            }
            .listRowBackground(Palette.surface)
        }
    }

    private var rolloverFooter: String {
        if settings.rolloverEnabled {
            return "Categories set to carry over move their leftover, or overspend, into the next period. Leave a limit empty to stop budgeting that category."
        }
        return "Carry over only takes effect once rollover is switched on in Settings. Leave a limit empty to stop budgeting that category."
    }

    // MARK: Bindings and saving

    private func limitBinding(for category: Category) -> Binding<Decimal> {
        let id: UUID = category.id
        let fallback: Decimal = category.budgetLimit
        return Binding<Decimal>(
            get: { limitDrafts[id] ?? fallback },
            set: { limitDrafts[id] = $0 }
        )
    }

    private func rollBinding(for category: Category) -> Binding<Bool> {
        let id: UUID = category.id
        let fallback: Bool = category.rollsOver
        return Binding<Bool>(
            get: { rollDrafts[id] ?? fallback },
            set: { rollDrafts[id] = $0 }
        )
    }

    private func save() {
        for category in categories {
            if let value = limitDrafts[category.id] {
                category.budgetLimit = max(value, 0)
            }
            if let roll = rollDrafts[category.id] {
                category.rollsOver = roll
            }
        }
        try? context.save()
        dismiss()
    }
}

/// One row in the limits editor: icon, name, amount field and a carry-over toggle.
struct BudgetLimitRow: View {
    let category: Category
    @Binding var limit: Decimal
    @Binding var rollsOver: Bool
    let rolloverEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CategoryIcon(category: category, size: 32)
                Text(category.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                AmountField(title: "No limit", amount: $limit)
                    .frame(maxWidth: 150)
                    .accessibilityLabel("\(category.name) limit")
            }
            Toggle("Carry leftover forward", isOn: $rollsOver)
                .font(.subheadline)
                .foregroundStyle(rolloverEnabled ? Palette.ink : Palette.inkTertiary)
                .disabled(!rolloverEnabled)
        }
        .padding(.vertical, 4)
    }
}
