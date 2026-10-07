import Foundation
import LocalAuthentication
import Observation

/// Face ID / Touch ID / passcode lock shown when the app opens or returns from the background.
@Observable
final class AppLockController {
    private(set) var isLocked = false
    private(set) var lastError: String?

    /// Locks if the user turned on app lock.
    func lockIfNeeded(settings: AppSettings) {
        if settings.appLockEnabled { isLocked = true }
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "Passcode")
        }
    }

    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    @MainActor
    func unlock() async {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock your budget"))
            if success {
                isLocked = false
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Used when the user turns the lock off.
    func forceUnlock() {
        isLocked = false
    }

    /// Confirms identity before enabling the lock, so users can't lock themselves out.
    @MainActor
    func verifyForEnabling() async -> Bool {
        let context = LAContext()
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Turn on app lock"))) ?? false
    }
}
