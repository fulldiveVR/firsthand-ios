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

/// Shows an invite link as a QR code with a share button.
struct InviteLinkSheet: View {
    let invite: AppModel.OutgoingInvite
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let name = invite.friendName, !name.isEmpty {
                    Text("Send this link to \(name) so they can see your moments.")
                        .multilineTextAlignment(.center)
                } else {
                    Text("Your friend scans this code with the iPhone camera, or opens the link.")
                        .multilineTextAlignment(.center)
                }
                if let image = QRCode.image(for: invite.url) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .accessibilityLabel("Invite QR code")
                }
                ShareLink(item: invite.url) {
                    Label("Send Link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                Text("The link works for one person. They need iCloud and \(AppInfo.name).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
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
