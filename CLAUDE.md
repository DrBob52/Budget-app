# Tally

Original SwiftUI + SwiftData budgeting app for iPhone (iOS 17), with a WidgetKit extension and a watchOS 10 companion. It covers the feature set of the Buddy budget planner with its own code, copy and design. See `docs/FEATURES.md` and `docs/ARCHITECTURE.md`.

## Product decisions

- Manual by design: every transaction is entered by hand. No bank sync and no statement import. Don't add either without asking.
- English and Spanish only. Every visible string needs a Spanish translation (CI enforces it).
- Shared budgets live on one device for now. Syncing between two people's phones (CloudKit `CKShare` or a backend) is planned for later.
- Visual style: warm paper background, ink text, serif numerals, hairline cards, muted earth tones, SF Symbols (no emoji). Use the design system, not ad hoc styling.

## Build and test

```sh
brew install xcodegen          # once
xcodegen generate              # after adding or moving files; Tally.xcodeproj is not committed
swift test --package-path Packages/TallyCore
xcodebuild build -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TallyTests
```

CI (`.github/workflows/ci.yml`) runs the same on macOS, then the Spanish coverage check.

## Code conventions

- Money is `Decimal`; `Transaction.amount` is always positive and `kind` gives direction.
- Budget, period, recurrence, split and insights math lives in `Packages/TallyCore` (pure Foundation, unit-tested). App code calls it through `BudgetService`.
- Shared UI lives in `Tally/DesignSystem`: `.tallyScreen()`, `.tallyCard()`, `MoneyText`, `AmountField`, `Overline`, `SectionHeader`, `CategoryIcon`, `CategoryPicker`, `PeriodNavigator`.
- New top-level types in a feature folder use that feature's prefix (`Budget…`, `Ledger…`, `Insights…`, `Wallet…`/`Account…`/`Goal…`, `Together…`, `Settings…`, `Onboarding…`, `Paywall…`, `Widget…`, `Watch…`).
- The SwiftData models `Transaction` and `Category` shadow SwiftUI/ObjC names inside the app module. In the test target write `Tally.Transaction` and `Tally.Category`. StoreKit's type is always `StoreKit.Transaction`.
- Deployment target is iOS 17: no iOS 18-only APIs (for example `OpenURLIntent`, `@Entry`).

## Localization

- Write UI text as `Text("...")`, `Button("...")` and similar literals, or `String(localized: "...")`. A plain `String` is never translated.
- Counts with a noun use inflection markup: `Text("^[\(count) day](inflect: true) left")`.
- Catalogs: `Tally/Resources/Localizable.xcstrings`, `TallyWidgets/Localizable.xcstrings`, `TallyWatch/Localizable.xcstrings`, Siri phrases in `Tally/Resources/AppShortcuts.xcstrings` (phrase sets), Info.plist text in `*/es.lproj/InfoPlist.strings`, TallyCore enum names in `Packages/TallyCore/Sources/TallyCore/Resources/*.lproj`.
- After adding UI text, export the exact keys (Xcode → Product → Export Localizations, or run the "Export strings" workflow on GitHub). Then:

```sh
python3 scripts/xliff_worklist.py Localization/es.xliff /tmp/worklist.json
# fill /tmp/translations.json as {"<i>": "<Spanish>"} for each worklist item
python3 scripts/apply_translations.py /tmp/worklist.json /tmp/translations.json es
python3 scripts/check_localizations.py <export dir>   # 0 missing = CI passes
```

## Before running on a device

Set `DEVELOPMENT_TEAM` in `project.yml`, replace the `com.tallybudget` bundle IDs and the `group.com.tallybudget.shared` App Group with your own, then run `xcodegen generate`. The Tally scheme uses `Configuration/Tally.storekit` for subscriptions in the simulator.
