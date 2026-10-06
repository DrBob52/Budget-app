import SwiftUI
import SwiftData

@main
struct TallyApp: App {
    @State private var settings = AppSettings.shared
    @State private var router = AppRouter()
    @State private var lock = AppLockController()
    @State private var store = ProStore()

    private let container = Persistence.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(router)
                .environment(lock)
                .environment(store)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(Palette.accent)
        }
        .modelContainer(container)
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension View {
    /// Injects the app-wide environment for SwiftUI previews.
    @MainActor
    func previewEnvironment() -> some View {
        self
            .environment(AppSettings.shared)
            .environment(AppRouter())
            .environment(AppLockController())
            .environment(ProStore())
            .modelContainer(Persistence.preview)
    }
}
