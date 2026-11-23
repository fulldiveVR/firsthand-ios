#if os(iOS)
import FirsthandCore
import CloudKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreTransferable
import SwiftUI
import UIKit

/// QR code of a URL, rendered with CoreImage. Nothing leaves the device.
enum QRCode {
    static func image(for url: URL, side: CGFloat = 600) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// System Messages / Mail invite for my share. The system adds the recipient as a participant.
struct ShareInvite: Transferable {
    let sharing: CloudKitSharing

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invite in
            .prepareShare(container: invite.sharing.container, allowedSharingOptions: .readOnlyPrivate) {
                try await invite.sharing.shareForSystemInvite()
            }
        }
    }
}

extension CKAllowedSharingOptions {
    /// Friends can only view, and only invited people can open the link.
    static var readOnlyPrivate: CKAllowedSharingOptions {
        CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readOnly, allowedParticipantAccessOptions: .specifiedRecipientsOnly)
    }
}

/// The invite as a Wallet-style pass: a tinted band, the QR code on a white plate, and the inviter's name.
struct InviteLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let invite: AppModel.OutgoingInvite

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let name = invite.friendName, !name.isEmpty {
                        Text("Send this to \(name) so they can see your moments too.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    InvitePass(url: invite.url, inviter: model.userName)
                    ShareLink(item: invite.url) {
                        Label("Send Link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// A boarding-pass style card. The QR plate stays white in dark mode so cameras can read it.
struct InvitePass: View {
    let url: URL
    var inviter: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sun.horizon.fill")
                    .font(.title3)
                    .accessibilityHidden(true)
                Text(AppInfo.name)
                    .font(.headline)
                Spacer()
                Text("Invite")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.mix(with: .pink, by: 0.35)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )

            VStack(spacing: 16) {
                if let image = QRCode.image(for: url) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 240)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                        .accessibilityLabel("Invite QR code")
                }
                VStack(spacing: 4) {
                    if let inviter, !inviter.isEmpty {
                        Text(inviter).font(.title3.bold())
                    }
                    Text("Scan with the iPhone camera. Works for one person.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pass, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

/// Invite a known person by the email or phone number of their Apple Account.
struct InviteContactSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var contact = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email or phone number", text: $contact)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Use the email or phone number of your friend's Apple Account. \(AppInfo.name) uses it only to find them in iCloud and does not store it.")
                }
            }
            .navigationTitle("Invite by Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") {
                        working = true
                        Task {
                            let done = await model.invite(contact: contact)
                            working = false
                            if done { dismiss() }
                        }
                    }
                    .disabled(working || contact.isEmpty)
                }
            }
        }
    }
}

/// Apple's sharing UI for my share: add people, copy the link, remove participants.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadOnly]
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onChange: () -> Void

        init(onChange: @escaping () -> Void) {
            self.onChange = onChange
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}

        func itemTitle(for csc: UICloudSharingController) -> String? {
            String(localized: "\(AppInfo.name) moments")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { onChange() }

        /// For the owner this is "Stop Sharing", which removes every friend at once.
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { onChange() }
    }
}
#endif
