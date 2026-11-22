#if os(iOS)
import CandidCore
import CloudKit
import Foundation

/// `ShareService` on top of `CloudKitSharing`. See that type for the data model.
struct CloudKitShareService: ShareService {
    let sharing: CloudKitSharing

    /// The zone is shared with every participant, so `friendIDs` only checks that someone will see it.
    func share(_ suggestion: Suggestion, imageData: Data, with friendIDs: [Friend.ID]) async throws -> Post {
        guard !friendIDs.isEmpty else { throw ShareError.noRecipients }
        return try await sharing.publish(caption: suggestion.caption, provenance: suggestion.provenance, imageData: imageData)
    }

    func feed() async throws -> [Post] { try await sharing.syncFeed() }

    func myPosts() async throws -> [Post] { try await sharing.syncMyPosts() }

    func deletePost(_ id: Post.ID) async throws { try await sharing.deletePost(id) }

    func deleteAllData() async throws { try await sharing.deleteAll() }
}

/// Friends are the participants of my share plus the owners of the shares I accepted.
struct CloudKitFriendDirectory: FriendDirectory {
    let sharing: CloudKitSharing

    func friends() async throws -> [Friend] {
        try await friendships().filter(\.state.isActive).map(\.asFriend)
    }

    func friendships() async throws -> [Friendship] { try await sharing.friendships() }

    func makeInviteURL() async throws -> URL { try await sharing.oneTimeInviteURL() }

    func invite(_ contact: InviteContact) async throws -> URL { try await sharing.invite(contact) }

    func shareBack(with friendID: Friend.ID) async throws -> URL { try await sharing.shareBack(with: friendID) }

    func remove(_ friendID: Friend.ID) async throws { try await sharing.remove(friendID) }

    func reset() async throws { try await sharing.resetRoster() }
}
#endif
