#if os(iOS)
import Foundation
import LocalAuthentication

/// Face ID or Touch ID confirms every share. The device passcode is the system fallback.
struct BiometricGate {
    enum GateError: Error {
        case unavailable
    }

    func confirmShare() async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Not now")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw GateError.unavailable
        }
        return try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: String(localized: "Confirm that you want to share this photo with your friends.")
        )
    }
}
#endif
