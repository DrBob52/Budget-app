import SwiftUI
import SwiftData
import TallyCore

// Shared pickers and editors used by several features.

/// Grid of SF Symbols.
struct SymbolGridPicker: View {
    @Binding var symbol: String
    var colorHex: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(SymbolCatalog.all, id: \.self) { name in
                Button {
                    symbol = name
                } label: {
                    CategoryIcon(symbol: name, colorHex: name == symbol ? colorHex : "#9C978C", size: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
                                .strokeBorder(name == symbol ? Color(hex: colorHex) : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(name == symbol ? .isSelected : [])
            }
        }
    }
}

/// Row of color swatches.
struct SwatchPicker: View {
    @Binding var colorHex: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Palette.swatches, id: \.self) { hex in
                Button {
                    colorHex = hex
                } label: {
                    RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
                        .fill(Color(hex: hex))
                        .frame(height: 34)
                        .overlay {
                            if hex == colorHex {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(hex)")
                .accessibilityAddTraits(hex == colorHex ? .isSelected : [])
            }
        }
    }
}

/// Create or edit a category. Pass `onSave` to receive the saved category (used for inline creation).
struct CategoryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let category: Category?
    var initialKind: CategoryKind = .expense
    var onSave: ((Category) -> Void)? = nil

    @State private var name = ""
    @State private var symbol = "tag"
    @State private var colorHex = Palette.swatches[0]
    @State private var kind: CategoryKind = .expense
    @State private var limit: Decimal = 0
    @State private var rollsOver = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CategoryIcon(symbol: symbol, colorHex: colorHex, size: 44)
                        TextField("Name", text: $name)
                            .font(.headlineSerif)
                    }
                    Picker("Type", selection: $kind) {
                        ForEach(CategoryKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if kind == .expense {
                    Section {
                        AmountField(title: "No limit", amount: $limit)
                        Toggle("Carry leftover to next period", isOn: $rollsOver)
                    } header: {
                        Text("Budget per period")
                    } footer: {
                        Text("Leave empty to track spending without a limit. Carry-over also needs rollover turned on in Settings.")
                    }
                }
                Section("Color") {
                    SwatchPicker(colorHex: $colorHex)
                        .padding(.vertical, 4)
                }
                Section("Icon") {
                    SymbolGridPicker(symbol: $symbol, colorHex: colorHex)
                        .padding(.vertical, 4)
                }
                if category != nil {
                    Section {
                        Button("Archive category", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Archived categories are hidden but their transactions keep their history.")
                    }
                }
            }
            .tallyScreen()
            .navigationTitle(category == nil ? "New category" : "Edit category")
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
            .confirmationDialog("Archive this category?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Archive", role: .destructive) {
                    category?.isArchived = true
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let category {
            name = category.name
            symbol = category.symbol
            colorHex = category.colorHex
            kind = category.kind
            limit = category.budgetLimit
            rollsOver = category.rollsOver
        } else {
            kind = initialKind
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let target: Category
        if let category {
            target = category
        } else {
            let count = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
            target = Category(name: trimmed, symbol: symbol, colorHex: colorHex, kind: kind, sortOrder: count)
            context.insert(target)
        }
        target.name = trimmed
        target.symbol = symbol
        target.colorHex = colorHex
        target.kind = kind
        target.budgetLimit = kind == .expense ? limit : 0
        target.rollsOver = kind == .expense && rollsOver
        try? context.save()
        onSave?(target)
        dismiss()
    }
}

/// Horizontal-wrapping grid of categories with an inline "New" tile.
struct CategoryPicker: View {
    @Query(filter: #Predicate<Category> { !$0.isArchived }, sort: \Category.sortOrder)
    private var categories: [Category]

    @Binding var selection: Category?
    let kind: CategoryKind

    @State private var showingNew = false

    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(categories.filter { $0.kind == kind }) { category in
                tile(for: category)
            }
            Button {
                showingNew = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius).strokeBorder(Palette.rule, style: StrokeStyle(lineWidth: 1, dash: [3])))
                    Text("New")
                        .font(.caption)
                }
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 70)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingNew) {
            CategoryEditorView(category: nil, initialKind: kind) { created in
                selection = created
            }
        }
    }

    private func tile(for category: Category) -> some View {
        let selected = selection?.id == category.id
        return Button {
            selection = category
        } label: {
            VStack(spacing: 6) {
                CategoryIcon(category: category)
                Text(category.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(selected ? Palette.sunken : .clear, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
                    .strokeBorder(selected ? Palette.ink : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Menu-style picker for accounts. `allowsNone` adds a "No account" option.
struct AccountPicker: View {
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    let title: LocalizedStringKey
    @Binding var selection: Account?
    var allowsNone = true
    var excluding: Account? = nil

    var body: some View {
        Picker(title, selection: $selection) {
            if allowsNone {
                Text("No account").tag(Account?.none)
            }
            ForEach(accounts.filter { $0.id != excluding?.id }) { account in
                Label(account.name, systemImage: account.symbol).tag(Account?.some(account))
            }
        }
    }
}

/// Menu-style picker for members of a shared budget.
struct MemberPicker: View {
    @Query(sort: \Member.createdAt) private var members: [Member]

    let title: LocalizedStringKey
    @Binding var selection: Member?

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(members) { member in
                (member.isMe ? Text("\(member.name) (you)") : Text(member.name)).tag(Member?.some(member))
            }
        }
    }
}
