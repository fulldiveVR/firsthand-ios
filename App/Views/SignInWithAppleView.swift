#if os(iOS)
import AuthenticationServices
import SwiftUI

struct SignInWithAppleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var failed = false

    var body: some View {
        VStack(spacing: 8) {
            SignInWithAppleButton(.signIn) { request in
                // No email: friends see only the name the user chooses.
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                    // TODO: Store the user id in the Keychain instead of UserDefaults.
                    model.appleUserID = credential.user
                case .failure:
                    failed = true
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)

            if failed {
                Text("Sign in did not complete. Try again.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}
#endif
