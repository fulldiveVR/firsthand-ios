#if os(iOS)
import AuthenticationServices
import CandidCore
import SwiftUI

@main
struct CandidApp: App {
    @State private var model = AppModel(services: .live)
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AnalysisScheduler.register(services: .live)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await model.checkAppleCredential()
                    await model.refresh()
                }
            case .background:
                AnalysisScheduler.schedule()
            default:
                break
            }
        }
    }
}

extension AppModel {
    /// Signs out locally when the Apple ID credential is revoked.
    func checkAppleCredential() async {
        guard let userID = appleUserID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        if state == .revoked || state == .notFound {
            appleUserID = nil
        }
    }
}
#endif
