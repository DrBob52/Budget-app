# Tally

A calm, paper-and-ink budgeting app for iPhone, with widgets and an Apple Watch companion. Plan a budget per category around your payday, log spending in a couple of taps, share costs with a partner or friends and settle up, save toward goals, and see where the money goes.

See [docs/FEATURES.md](docs/FEATURES.md) for the full feature list and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organised.

## Requirements

- Xcode 16 or newer, iOS 17+, watchOS 10+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```sh
xcodegen generate
open Tally.xcodeproj
```

Before running on a device:

1. In `project.yml`, set `DEVELOPMENT_TEAM` and change the `com.tallybudget` bundle IDs to your own (search the repo for `com.tallybudget` and `group.com.tallybudget.shared`).
2. Run `xcodegen generate` again.
3. In the Apple Developer portal, register the App Group so the widget and app can share data.

The `Tally` scheme uses `Configuration/Tally.storekit`, so subscriptions work in the simulator without App Store Connect.

## Tests

```sh
swift test --package-path Packages/TallyCore    # budget math, periods, splits, import
xcodebuild test -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI (`.github/workflows/ci.yml`) runs both on a macOS runner on every push.

## Optional: iCloud sync

Set `Persistence.cloudSyncEnabled = true`, add the iCloud capability with CloudKit and a container in Xcode, and SwiftData syncs data across the user's own devices.
