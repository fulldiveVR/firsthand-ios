import Foundation
import Testing
@testable import CandidCore

@Suite struct FriendshipTests {
    let empty = Friendship(id: "b", displayName: "Bea")

    @Test func noSidesIsRemoved() {
        #expect(empty.state == .removed)
    }

    @Test func ownerPathInvitedThenOneWayOutgoingThenMutual() throws {
        let invited = try empty.applying(.sentInvite)
        #expect(invited.state == .invited)
        let outgoing = try invited.applying(.theyAccepted)
        #expect(outgoing.state == .oneWay(.outgoing))
        #expect(!outgoing.needsReverseShare)
        // They shared back: I open their link and accept.
        let pending = try outgoing.applying(.receivedInvite)
        #expect(pending.state == .oneWay(.outgoing))
        let mutual = try pending.applying(.iAccepted)
        #expect(mutual.state == .mutual)
    }

    @Test func receiverPathPendingThenOneWayIncomingNeedsReverseShare() throws {
        let pending = try empty.applying(.receivedInvite)
        #expect(pending.state == .pendingAccept)
        let incoming = try pending.applying(.iAccepted)
        #expect(incoming.state == .oneWay(.incoming))
        #expect(incoming.needsReverseShare)
        let reverse = try incoming.applying(.sentInvite)
        #expect(reverse.state == .oneWay(.incoming))
        #expect(!reverse.needsReverseShare)
        #expect(try reverse.applying(.theyAccepted).state == .mutual)
    }

    @Test func acceptWithoutInviteIsInvalid() {
        #expect(throws: FriendshipError.invalidTransition(from: .removed, event: .theyAccepted)) {
            try empty.applying(.theyAccepted)
        }
        #expect(throws: FriendshipError.invalidTransition(from: .removed, event: .iAccepted)) {
            try empty.applying(.iAccepted)
        }
    }

    @Test func eventsAreIdempotent() throws {
        let mutual = Friendship(id: "b", displayName: "Bea", outgoing: .accepted, incoming: .accepted)
        #expect(try mutual.applying(.sentInvite) == mutual)
        #expect(try mutual.applying(.receivedInvite) == mutual)
        #expect(try mutual.applying(.theyAccepted) == mutual)
        #expect(try mutual.applying(.iAccepted) == mutual)
    }

    @Test func oneSideEndingLeavesOneWay() throws {
        let mutual = Friendship(id: "b", displayName: "Bea", outgoing: .accepted, incoming: .accepted)
        #expect(try mutual.applying(.theyLeftMyShare).state == .oneWay(.incoming))
        #expect(try mutual.applying(.theirShareEnded).state == .oneWay(.outgoing))
        #expect(try mutual.applying(.theyLeftMyShare).applying(.theirShareEnded).state == .removed)
    }

    @Test func removeEndsBothSides() throws {
        let mutual = Friendship(id: "b", displayName: "Bea", outgoing: .accepted, incoming: .accepted)
        let removed = try mutual.applying(.iRemoved)
        #expect(removed.state == .removed)
        // A removed friend can be invited again.
        #expect(try removed.applying(.sentInvite).state == .invited)
    }

    @Test func asFriendMapsAcceptedSides() {
        #expect(Friendship(id: "b", displayName: "B", outgoing: .invited).asFriend.status == .invited)
        #expect(Friendship(id: "b", displayName: "B", incoming: .pending).asFriend.status == .invited)
        #expect(Friendship(id: "b", displayName: "B", incoming: .accepted).asFriend.status == .accepted)
    }
}

@Suite struct FriendRosterTests {
    @Test func capIsFiftyByDefault() {
        #expect(FriendRoster.defaultLimit == 50)
        #expect(FriendRoster.defaultLimit <= 100)  // CloudKit participants per share
    }

    @Test func fiftyFirstFriendIsRejected() throws {
        var roster = FriendRoster()
        for i in 0..<50 { try roster.apply(.sentInvite, to: "f\(i)") }
        #expect(roster.activeCount == 50)
        #expect(!roster.canAddFriend)
        #expect(throws: FriendshipError.friendLimitReached(limit: 50)) {
            try roster.apply(.sentInvite, to: "f50")
        }
        #expect(throws: FriendshipError.friendLimitReached(limit: 50)) {
            try roster.apply(.receivedInvite, to: "f51")
        }
        #expect(roster.friendships.count == 50)
    }

    @Test func existingFriendCanProgressAtTheCap() throws {
        var roster = FriendRoster(limit: 2)
        try roster.apply(.sentInvite, to: "a")
        try roster.apply(.receivedInvite, to: "b")
        try roster.apply(.theyAccepted, to: "a")
        try roster.apply(.iAccepted, to: "b")
        try roster.apply(.sentInvite, to: "b")  // reverse share does not add a friend
        #expect(roster["a"]?.state == .oneWay(.outgoing))
        #expect(roster["b"]?.state == .oneWay(.incoming))
    }

    @Test func removingFreesASlot() throws {
        var roster = FriendRoster(limit: 1)
        try roster.apply(.sentInvite, to: "a")
        try roster.apply(.iRemoved, to: "a")
        #expect(roster.canAddFriend)
        try roster.apply(.sentInvite, to: "b")
        #expect(roster.activeCount == 1)
        #expect(roster["a"]?.state == .removed)
    }

    @Test func applyUpdatesDisplayNameOnlyWhenGiven() throws {
        var roster = FriendRoster()
        try roster.apply(.sentInvite, to: "a", displayName: "Ann")
        try roster.apply(.theyAccepted, to: "a")
        #expect(roster["a"]?.displayName == "Ann")
        try roster.apply(.theyAccepted, to: "a", displayName: "Ann B")
        #expect(roster["a"]?.displayName == "Ann B")
    }

    @Test func reconcileTakesCloudKitStateAndKeepsLocalPending() throws {
        var roster = FriendRoster()
        try roster.apply(.sentInvite, to: "a", displayName: "Ann")
        try roster.apply(.receivedInvite, to: "p", displayName: "Pat")
        try roster.apply(.receivedInvite, to: "gone", displayName: "Gus")
        try roster.apply(.iAccepted, to: "gone")

        roster.reconcile(with: SharingSnapshot(
            outgoing: [
                .init(id: "a", displayName: "", accepted: true),
                .init(id: "n", displayName: "Neo", accepted: false),
            ],
            incoming: [.init(id: "a", displayName: "Ann", accepted: true)]
        ))

        #expect(roster["a"]?.state == .mutual)
        #expect(roster["a"]?.displayName == "Ann")
        #expect(roster["n"]?.state == .invited)
        #expect(roster["p"]?.state == .pendingAccept)
        #expect(roster["gone"]?.state == .removed)
        #expect(roster.friendships.map(\.id) == ["a", "p", "gone", "n"])
    }

    @Test func reconcileTurnsAcceptedPendingIntoIncoming() throws {
        var roster = FriendRoster()
        try roster.apply(.receivedInvite, to: "p", displayName: "Pat")
        roster.reconcile(with: SharingSnapshot(incoming: [.init(id: "p", displayName: "Pat", accepted: true)]))
        #expect(roster["p"]?.state == .oneWay(.incoming))
        #expect(roster["p"]?.needsReverseShare == true)
    }

    @Test func rosterRoundTripsThroughJSON() throws {
        var roster = FriendRoster()
        try roster.apply(.sentInvite, to: "a", displayName: "Ann")
        let data = try JSONEncoder().encode(roster)
        #expect(try JSONDecoder().decode(FriendRoster.self, from: data) == roster)
    }

    @Test func inMemoryDirectoryFollowsTheStateMachine() async throws {
        let directory = InMemoryFriendDirectory(limit: 1)
        _ = try await directory.invite(.email("ann@example.com"))
        #expect(await directory.friends().map(\.status) == [.invited])
        try await directory.simulate(.theyAccepted, for: "ann@example.com")
        #expect(await directory.friends().map(\.status) == [.accepted])
        await #expect(throws: FriendshipError.friendLimitReached(limit: 1)) {
            try await directory.invite(.phone("+15550100"))
        }
        try await directory.remove("ann@example.com")
        #expect(await directory.friends().isEmpty)
        await #expect(throws: FriendshipError.unknownFriend("x")) {
            try await directory.shareBack(with: "x")
        }
    }
}

@Suite struct InviteContactTests {
    @Test func parsesEmail() {
        #expect(InviteContact.parse("  Ann@Example.com ") == .email("ann@example.com"))
    }

    @Test func parsesPhone() {
        #expect(InviteContact.parse("+1 (555) 010-0100") == .phone("+15550100100"))
        #expect(InviteContact.parse("555 0100 12") == .phone("555010012"))
    }

    @Test func rejectsGarbage() {
        for raw in ["", "   ", "ann@", "@x.com", "a@b", "a@.com", "a b@c.com", "12345", "call me", "a@b@c.com"] {
            #expect(InviteContact.parse(raw) == nil, "\(raw)")
        }
    }
}
