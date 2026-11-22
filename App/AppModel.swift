#if os(iOS)
import CandidCore
import CloudKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum ShareState: Equatable {
        case idle
        case working
        case failed(String)
    }

    let services: AppServices
    private let gate = BiometricGate()

    var appleUserID: String? {
        didSet { UserDefaults.standard.set(appleUserID, forKey: Self.userKey) }
    }
    var photoAccess: PhotoAuthorization = .notDetermined
    var pending: Suggestion?
    var friends: [Friend] = []
    var friendships: [Friendship] = []
    /// Friends' posts and my own posts, newest first.
    var feed: [Post] = []
    var shareState: ShareState = .idle
    /// Set after I accepted a friend's share and did not share back yet. The UI asks once.
    var reverseShareOffer: Friendship?
    /// A link to send, shown in a sheet with a QR code.
    var outgoingInvite: OutgoingInvite?
    var sharingError: String?

    struct OutgoingInvite: Identifiable, Equatable {
        var id: URL { url }
        var url: URL
        var friendName: String?
    }

    private static let userKey = "appleUserID"

    init(services: AppServices) {
        self.services = services
        appleUserID = UserDefaults.standard.string(forKey: Self.userKey)
    }

    var isOnboarded: Bool { appleUserID != nil && photoAccess.canRead }

    func refresh() async {
        photoAccess = await services.library.authorizationStatus()
        pending = await services.history.load().pending
        await refreshSharing()
    }

    /// Friends from CloudKit, then friends' posts and my posts.
    func refreshSharing() async {
        if let list = try? await services.friends.friendships() {
            friendships = list.filter(\.state.isActive)
            friends = friendships.map(\.asFriend)
        }
        let theirs = (try? await services.shareService.feed()) ?? feed.filter { $0.authorID != CloudKitSharing.ownOwnerID }
        let mine = (try? await services.shareService.myPosts()) ?? feed.filter { $0.authorID == CloudKitSharing.ownOwnerID }
        feed = Post.chronological(theirs + mine)
    }

    func attachSharingInbox() {
        SharingInbox.shared.attach(
            onShare: { [weak self] metadata in await self?.accept(metadata) },
            onFeedChange: { [weak self] in await self?.refreshSharing() }
        )
    }

    // MARK: Friends

    /// The user opened a friend's share link. Opening it is the consent, so the app accepts it.
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            let friendship = try await services.sharing.accept(metadata)
            await refreshSharing()
            let current = friendships.first { $0.id == friendship.id } ?? friendship
            if current.needsReverseShare { reverseShareOffer = current }
        } catch FriendshipError.friendLimitReached(let limit) {
            sharingError = String(localized: "You already have \(limit) friends. Remove one to accept this invite.")
        } catch CloudKitSharing.SharingError.ownShare {
            // The user opened their own link. Nothing to do.
        } catch {
            sharingError = String(localized: "Could not accept the invite. Check that iCloud is on and try again.")
        }
    }

    /// Reverse share: lets the friend whose share I accepted see my posts too.
    func shareBack(with friendship: Friendship) async {
        reverseShareOffer = nil
        do {
            let url = try await services.friends.shareBack(with: friendship.id)
            outgoingInvite = OutgoingInvite(url: url, friendName: friendship.displayName)
            await refreshSharing()
        } catch {
            sharingError = Self.message(for: error)
        }
    }

    /// QR and AirDrop invite. Any one person who opens the link can join.
    func makeInvite() async {
        do {
            outgoingInvite = OutgoingInvite(url: try await services.friends.makeInviteURL())
        } catch {
            sharingError = Self.message(for: error)
        }
    }

    func invite(contact raw: String) async -> Bool {
        guard let contact = InviteContact.parse(raw) else {
            sharingError = String(localized: "Enter an email address or a phone number.")
            return false
        }
        do {
            outgoingInvite = OutgoingInvite(url: try await services.friends.invite(contact))
            await refreshSharing()
            return true
        } catch {
            sharingError = Self.message(for: error)
            return false
        }
    }

    func remove(_ friendship: Friendship) async {
        do {
            try await services.friends.remove(friendship.id)
        } catch {
            sharingError = String(localized: "Could not remove the friend. Try again later.")
        }
        await refreshSharing()
    }

    func delete(_ post: Post) async {
        do {
            try await services.shareService.deletePost(post.id)
            feed.removeAll { $0.feedItemID == post.feedItemID }
        } catch {
            sharingError = String(localized: "Could not delete the post. Try again later.")
        }
    }

    var friendCapText: String {
        String(localized: "\(friendships.count) of \(FriendRoster.defaultLimit) friends")
    }

    private static func message(for error: Error) -> String {
        switch error {
        case FriendshipError.friendLimitReached(let limit):
            String(localized: "You can have up to \(limit) friends.")
        case CloudKitSharing.SharingError.participantNotFound:
            String(localized: "No iCloud account was found for this contact.")
        case let error as CKError where error.code == .notAuthenticated:
            String(localized: "Sign in to iCloud in Settings to share with friends.")
        default:
            String(localized: "Something went wrong. Try again later.")
        }
    }

    func requestPhotoAccess() async {
        photoAccess = await services.library.requestAuthorization()
        _ = await services.notifier.requestAuthorization()
        AnalysisScheduler.schedule()
    }

    /// Share needs Face ID or Touch ID every time. Only approved friends receive the photo.
    func share() async {
        guard let suggestion = pending else { return }
        shareState = .working
        do {
            guard try await gate.confirmShare() else {
                shareState = .idle
                return
            }
            guard let data = try await services.library.imageData(for: suggestion.assetID) else {
                shareState = .failed(String(localized: "This photo is no longer on your iPhone."))
                return
            }
            // The zone is shared with all participants. Anyone in my share will see the post.
            let recipients = friendships.filter { $0.outgoing != .none }.map(\.id)
            _ = try await services.shareService.share(suggestion, imageData: data, with: recipients)
            try await decide(.share, for: suggestion)
            shareState = .idle
        } catch ShareError.noRecipients {
            shareState = .failed(String(localized: "Add a friend first."))
        } catch {
            shareState = .failed(String(localized: "Sharing failed. Try again later."))
        }
    }

    func skip() async {
        guard let suggestion = pending else { return }
        try? await decide(.skip, for: suggestion)
    }

    private func decide(_ decision: ShareDecision, for suggestion: Suggestion) async throws {
        var history = await services.history.load()
        history.record(decision, for: suggestion.id)
        try await services.history.save(history)
        pending = nil
    }

    func deleteAllData() async {
        try? await services.deleteAllLocalAndSharedData()
        appleUserID = nil
        pending = nil
        feed = []
        friends = []
        friendships = []
    }

    #if DEBUG
    func analyzeNow() async {
        _ = try? await services.runAnalysis()
        await refresh()
    }
    #endif
}
#endif
