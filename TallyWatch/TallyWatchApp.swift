import SwiftUI

@main
struct TallyWatchApp: App {
    @StateObject private var model = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
        }
    }
}

struct WatchRootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                WatchSummaryView()
            }
            NavigationStack {
                WatchCategoriesView()
            }
            NavigationStack {
                WatchQuickLogView()
            }
        }
        .tabViewStyle(.verticalPage)
        .background(WatchPalette.paper)
    }
}
