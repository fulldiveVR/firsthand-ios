#if os(iOS)
import AuthenticationServices
import FirsthandCore
import SwiftUI

@main
struct FirsthandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel(services: .live)
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AnalysisScheduler.register(services: .live)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { model.attachSharingInbox() }
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
