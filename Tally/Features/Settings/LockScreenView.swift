import SwiftUI

/// Full-screen cover shown while the app is locked.
struct LockScreenView: View {
    @Environment(AppLockController.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    @State private var isAttempting = false
    @State private var wasBackgrounded = false

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                glyph
                Text("Tally")
                    .font(.display(44))
                    .foregroundStyle(Palette.ink)
                Text("Your budget is locked.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                if let message = lock.lastError {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.negative)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await attemptUnlock() }
                } label: {
                    Text("Unlock with \(lock.biometryName)")
                }
                .buttonStyle(.tallyPrimary)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .task {
            await attemptUnlock()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                wasBackgrounded = true
            } else if phase == .active && wasBackgrounded {
                wasBackgrounded = false
                Task { await attemptUnlock() }
            }
        }
    }

    private var glyph: some View {
        Image(systemName: "lock")
            .font(.system(size: 40, weight: .light))
            .foregroundStyle(Palette.ink)
            .frame(width: 88, height: 88)
            .background(Palette.surface, in: Circle())
            .overlay(Circle().strokeBorder(Palette.rule, lineWidth: Metrics.hairline))
            .accessibilityHidden(true)
    }

    @MainActor
    private func attemptUnlock() async {
        guard !isAttempting else { return }
        isAttempting = true
        await lock.unlock()
        isAttempting = false
    }
}

#Preview {
    LockScreenView()
        .previewEnvironment()
}
