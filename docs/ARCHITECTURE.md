# Tally architecture

Tally is a SwiftUI + SwiftData app for iOS 17+, with a WidgetKit extension and a watchOS app.

## Layout

| Path | What lives there |
| --- | --- |
| `Packages/TallyCore` | Pure-Foundation logic shared by every target: money formatting, budget periods, recurrence, budget/rollover math, insights, split + settle-up, CSV/OFX import, widget snapshot. Unit-tested with `swift test`. |
| `Tally/Models` | SwiftData models (`Category`, `Account`, `Transaction`, `RecurringTemplate`, `SavingsGoal`, `GoalContribution`, `Member`, `SplitShare`, `Settlement`). CloudKit-compatible: every attribute has a default, every relationship is optional. |
| `Tally/Services` | `AppSettings` (preferences in App Group defaults), `Persistence` (container + sample data), `BudgetService` (models → TallyCore), `SnapshotService` (widget/watch snapshot), `AppRouter` (tabs, sheets, `tally://` links), `AppLockController` (Face ID). |
| `Tally/DesignSystem` | Palette, fonts, metrics and shared components (`tallyCard`, `MoneyText`, `AmountField`, `BudgetBar`, `ProgressRing`, `CategoryIcon`, `CategoryPicker`, `CategoryEditorView`, `AccountPicker`, `MemberPicker`, `PeriodNavigator`, button styles, `EmptyStateView`). |
| `Tally/Features/*` | One folder per feature. Each owns its screens. |
| `TallyWidgets` | Home and Lock Screen widgets. Read `BudgetSnapshot` from the App Group. |
| `TallyWatch` | watchOS app. Receives the snapshot over WatchConnectivity and sends quick expenses back. |

## Rules

- Amounts are `Decimal`, always positive on `Transaction`; `kind` gives direction.
- Calculations go through TallyCore (`BudgetService.summary`, `InsightsCalculator`, `SplitCalculator`) so they are tested once.
- Environment objects available everywhere: `AppSettings`, `AppRouter`, `AppLockController`, `ProStore`, plus `\.modelContext`.
- Screens use `.tallyScreen()` for the paper background and `.tallyCard()` for cards. Money is shown with `MoneyText`.
- `RootView` refreshes the widget snapshot after every `ModelContext` save, so features just call `try? context.save()`.

## Deep links

- `tally://add` / `tally://add?kind=income`: quick add sheet
- `tally://tab/<budget|ledger|insights|wallet|together>`
- `tally://settings`
