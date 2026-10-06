import SwiftUI
import SwiftData

private struct TogetherDraftPerson: Identifiable {
    let id: UUID = UUID()
    var name: String = ""
    var colorHex: String
}

/// First-time setup: your name, plus the people you share with.
struct TogetherSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(ProStore.self) private var store

    @Query(sort: \Member.createdAt) private var members: [Member]

    @State private var myName: String = ""
    @State private var drafts: [TogetherDraftPerson] = []
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $myName)
                        .textContentType(.name)
                } header: {
                    Overline("You")
                } footer: {
                    Text("This is how you appear next to shared expenses.")
                }
                .listRowBackground(Palette.surface)

                Section {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Name", text: $draft.name)
                                .textContentType(.name)
                            SwatchPicker(colorHex: $draft.colorHex)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        drafts.remove(atOffsets: offsets)
                        if drafts.isEmpty { appendDraft() }
                    }

                    Button {
                        addPerson()
                    } label: {
                        Label("Add another person", systemImage: "plus")
                    }
                } header: {
                    Overline("People you share with")
                }
                .listRowBackground(Palette.surface)
            }
            .tallyScreen()
            .navigationTitle("Set up Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    // MARK: - State

    private var existingMe: Member? { members.first(where: { $0.isMe }) }

    private var trimmedMyName: String {
        myName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var namedDrafts: [TogetherDraftPerson] {
        drafts.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var canSave: Bool {
        !trimmedMyName.isEmpty && !namedDrafts.isEmpty
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        myName = existingMe?.name ?? ""
        if drafts.isEmpty { appendDraft() }
    }

    /// Next swatch not already used by a member or a draft.
    private func nextColorHex() -> String {
        var used: Set<String> = Set(members.map { $0.colorHex })
        for draft in drafts { used.insert(draft.colorHex) }
        let free: String? = Palette.swatches.first(where: { !used.contains($0) })
        if let free { return free }
        let swatches: [String] = Palette.swatches
        return swatches[(members.count + drafts.count) % swatches.count]
    }

    private func appendDraft() {
        drafts.append(TogetherDraftPerson(colorHex: nextColorHex()))
    }

    private func addPerson() {
        guard store.isUnlocked(.sharedBudgets) else {
            showPaywall()
            return
        }
        appendDraft()
    }

    /// The paywall lives on the root view, so close this sheet first.
    private func showPaywall() {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            router.sheet = .paywall
        }
    }

    private func save() {
        guard canSave else { return }
        guard store.isUnlocked(.sharedBudgets) else {
            showPaywall()
            return
        }

        if let me = existingMe {
            me.name = trimmedMyName
        } else {
            let swatches: [String] = Palette.swatches
            let used: Set<String> = Set(drafts.map { $0.colorHex })
            let color: String = swatches.first(where: { !used.contains($0) }) ?? swatches[0]
            context.insert(Member(name: trimmedMyName, colorHex: color, isMe: true))
        }

        for draft in namedDrafts {
            let name: String = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            context.insert(Member(name: name, colorHex: draft.colorHex))
        }

        try? context.save()
        dismiss()
    }
}

#Preview {
    TogetherSetupView()
        .previewEnvironment()
}
