#if os(iOS)
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text(AppInfo.name)
                .font(.largeTitle.bold())
            Text("Your iPhone finds one meaningful moment and suggests a real photo to share with your friends. Nothing is posted unless you say yes.")
                .font(.title3)

            VStack(alignment: .leading, spacing: 12) {
                Label("Photos are analyzed on this iPhone only.", systemImage: "iphone")
                Label("One suggestion at a time. Share or skip.", systemImage: "hand.thumbsup")
                Label("Face ID confirms every share.", systemImage: "faceid")
                Label("Friends only. No public profile.", systemImage: "person.2")
            }
            .foregroundStyle(.secondary)

            Spacer()

            if model.appleUserID == nil {
                SignInWithAppleView()
            } else if !model.photoAccess.canRead {
                photoAccessStep
            } else {
                firstScanStep
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var firstScanStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.firstScan {
            case .notStarted:
                Text("\(AppInfo.name) looks at your photos from the last few days on this iPhone. You can leave the app while it works.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Find my moments") { model.startFirstScan() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            case .scanning(let completed, let total):
                if total > 0 {
                    ProgressView(value: Double(completed), total: Double(total)) {
                        Text("Finding your moments")
                    } currentValueLabel: {
                        Text("\(completed) of \(total) photos")
                    }
                } else {
                    ProgressView("Finding your moments")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var photoAccessStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allow full photo access so \(AppInfo.name) can look at new photos while your iPhone charges. Screenshots are always ignored.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if model.photoAccess == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            } else {
                Button("Allow Photo Access") {
                    Task { await model.requestPhotoAccess() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
#endif
