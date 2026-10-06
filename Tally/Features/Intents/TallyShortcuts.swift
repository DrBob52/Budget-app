import AppIntents

struct TallyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add an expense to \(.applicationName)",
                "Record spending in \(.applicationName)"
            ],
            shortTitle: "Log expense",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CheckBudgetIntent(),
            phrases: [
                "How much is left in \(.applicationName)",
                "Check my budget in \(.applicationName)",
                "What can I spend in \(.applicationName)"
            ],
            shortTitle: "Left to spend",
            systemImageName: "gauge.with.dots.needle.33percent"
        )
        AppShortcut(
            intent: OpenQuickAddIntent(),
            phrases: [
                "Open quick add in \(.applicationName)",
                "New transaction in \(.applicationName)"
            ],
            shortTitle: "Quick add",
            systemImageName: "square.and.pencil"
        )
    }
}
