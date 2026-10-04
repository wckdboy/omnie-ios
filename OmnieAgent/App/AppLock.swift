import SwiftUI
import LocalAuthentication
import Observation

/// Optional Face ID / passcode gate, applied when the app returns from the
/// background.
@Observable
final class AppLock {
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "omnie.lock") }
    }
    private(set) var isLocked: Bool
    private var authenticating = false

    init() {
        let enabled = UserDefaults.standard.bool(forKey: "omnie.lock")
        isEnabled = enabled
        isLocked = enabled
    }

    func didEnterBackground() {
        if isEnabled { isLocked = true }
    }

    func unlockIfNeeded() {
        guard isLocked, !authenticating else { return }
        authenticating = true
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Omnie") { success, _ in
            Task { @MainActor in
                self.authenticating = false
                if success { self.isLocked = false }
            }
        }
    }
}

struct LockScreen: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(spacing: 24) {
            Wordmark(size: 30)
            Button("Unlock") { lock.unlockIfNeeded() }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.background.ignoresSafeArea())
    }
}
