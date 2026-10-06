import AppIntents
import Foundation

struct OpenQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Open quick add"
    static var description = IntentDescription("Open Tally on the add transaction sheet.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // The app is brought to the foreground; RootView routes the pending link.
        if let url = URL(string: "tally://add") {
            IntentRouting.open(url)
        }
        return .result()
    }
}

/// Hands deep links from intents that open the app to RootView, including on a cold launch.
@MainActor
enum IntentRouting {
    private(set) static var pendingURL: URL?

    static func open(_ url: URL) {
        pendingURL = url
        NotificationCenter.default.post(name: .intentOpenURL, object: url)
    }

    static func consume() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }
}

extension Notification.Name {
    static let intentOpenURL = Notification.Name("tally.intentOpenURL")
}
