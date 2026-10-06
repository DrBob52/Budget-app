import SwiftUI
import SwiftData

/// What the member editor sheet is working on.
enum TogetherMemberEditorTarget: Identifiable {
    case new
    case edit(Member)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let member): return member.id.uuidString
        }
    }
}

/// Everyone in the shared budget: rename, recolor, remove, add.
struct TogetherMembersView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(ProStore.self) private var store

    @Query(sort: \Member.createdAt) private var members: [Member]

    @State private var editorTarget: TogetherMemberEditorTarget?
    @State private var memberToDelete: Member?
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                ForEach(members) { member in
                    Button {
                        editorTarget = .edit(member)
                    } label: {
                        row(for: member)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Palette.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !member.isMe {
                            Button(role: .destructive) {
                                requestDelete(member)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                SectionHeader("People").textCase(nil)
            } footer: {
                Text("Removing someone also removes their share of past expenses and any repayments they were part of, so balances can change.")
            }

            Section {
                Button {
                    addPerson()
                } label: {
                    Label("Add person", systemImage: "plus")
                }
                .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.insetGrouped)
        .tallyScreen()
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addPerson()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add person")
            }
        }
        .sheet(item: $editorTarget) { target in
            TogetherMemberEditor(target: target)
        }
        .confirmationDialog(
            "Remove this person?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible,
            presenting: memberToDelete
        ) { member in
            Button("Remove \(member.name)", role: .destructive) {
                delete(member)
            }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text("\(member.name)'s shares and repayments will be deleted. Expenses they paid stay in your ledger.")
        }
    }

    private func row(for member: Member) -> some View {
        HStack(spacing: 12) {
            MemberAvatar(member: member, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                if member.isMe {
                    Text("You")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.inkTertiary)
        }
        .contentShape(Rectangle())
    }

    private func addPerson() {
        if store.isUnlocked(.sharedBudgets) {
            editorTarget = .new
        } else {
            router.sheet = .paywall
        }
    }

    private func requestDelete(_ member: Member) {
        guard !member.isMe else { return }
        memberToDelete = member
        confirmingDelete = true
    }

    private func delete(_ member: Member) {
        guard !member.isMe else { return }
        context.delete(member)
        try? context.save()
        memberToDelete = nil
    }
}

/// Add a person, or rename / recolor an existing one.
struct TogetherMemberEditor: View {
    let target: TogetherMemberEditorTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Member.createdAt) private var members: [Member]

    @State private var name: String = ""
    @State private var colorHex: String = Palette.swatches[0]
    @State private var didLoad = false
    @State private var confirmingDelete = false

    private var editingMember: Member? {
        if case .edit(let member) = target { return member }
        return nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                } header: {
                    Overline("Name")
                }
                .listRowBackground(Palette.surface)

                Section {
                    SwatchPicker(colorHex: $colorHex)
                        .padding(.vertical, 4)
                } header: {
                    Overline("Color")
                }
                .listRowBackground(Palette.surface)

                if let member = editingMember, !member.isMe {
                    Section {
                        Button("Remove person", role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .tallyScreen()
            .navigationTitle(editingMember == nil ? "Add person" : "Edit person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog(
                "Remove this person?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) { deleteMember() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their shares and repayments will be deleted, so balances can change.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let member = editingMember {
            name = member.name
            colorHex = member.colorHex
        } else {
            let used: Set<String> = Set(members.map { $0.colorHex })
            let swatches: [String] = Palette.swatches
            colorHex = swatches.first(where: { !used.contains($0) }) ?? swatches[members.count % swatches.count]
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let member = editingMember {
            member.name = trimmedName
            member.colorHex = colorHex
        } else {
            context.insert(Member(name: trimmedName, colorHex: colorHex))
        }
        try? context.save()
        dismiss()
    }

    private func deleteMember() {
        guard let member = editingMember, !member.isMe else { return }
        context.delete(member)
        try? context.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        TogetherMembersView()
    }
    .previewEnvironment()
}
