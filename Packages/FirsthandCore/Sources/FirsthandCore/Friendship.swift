import Foundation

/// A friendship is two CloudKit shares: my zone shared with them, and their zone shared with me.
/// Each side is tracked on its own. `state` is the product view of both sides.
public enum FriendshipState: Sendable, Hashable, Codable {
    public enum Direction: String, Sendable, Hashable, Codable {
        /// I accepted their share. I see their posts, they do not see mine.
        case incoming
        /// They accepted my share. They see my posts, I do not see theirs.
        case outgoing
    }

    /// I added them to my share. They did not accept yet.
    case invited
    /// I opened their invite. I did not accept yet.
    case pendingAccept
    case oneWay(Direction)
    /// Both shares are accepted.
    case mutual
    case removed

    /// The friend occupies a slot in the friend cap.
    public var isActive: Bool { self != .removed }
}

/// Events from the UI or from CloudKit. Every event is idempotent where that makes sense,
/// because CloudKit snapshots and user actions can repeat.
public enum FriendshipEvent: Sendable, Hashable, Codable {
    /// I added them as a participant of my share.
    case sentInvite
    /// I opened the URL of their share.
    case receivedInvite
    /// Their participant in my share became accepted.
    case theyAccepted
    /// I accepted their share.
    case iAccepted
    /// They left my share, or the participant is gone from my share.
    case theyLeftMyShare
    /// Their share is gone from my shared database (they removed me or deleted their zone).
    case theirShareEnded
    /// I removed them from my share and left their share.
    case iRemoved
}

public enum FriendshipError: Error, Equatable, Sendable {
    case invalidTransition(from: FriendshipState, event: FriendshipEvent)
    case friendLimitReached(limit: Int)
    case unknownFriend(String)
}

public struct Friendship: Sendable, Hashable, Codable, Identifiable {
    /// My share as seen from this friend.
    public enum Outgoing: String, Sendable, Hashable, Codable {
        case none, invited, accepted
    }

    /// Their share as seen from me.
    public enum Incoming: String, Sendable, Hashable, Codable {
        case none, pending, accepted
    }

    /// The friend's CloudKit user record name. The owner name of their zone has the same value.
    public var id: String
    public var displayName: String
    public var outgoing: Outgoing
    public var incoming: Incoming

    public init(id: String, displayName: String, outgoing: Outgoing = .none, incoming: Incoming = .none) {
        self.id = id
        self.displayName = displayName
        self.outgoing = outgoing
        self.incoming = incoming
    }

    public var state: FriendshipState {
        switch (outgoing, incoming) {
        case (.accepted, .accepted): .mutual
        case (.accepted, _): .oneWay(.outgoing)
        case (_, .accepted): .oneWay(.incoming)
        case (_, .pending): .pendingAccept
        case (.invited, _): .invited
        case (.none, .none): .removed
        }
    }

    /// I see their posts but they do not see mine, and I did not invite them back yet.
    /// The app then offers the reverse share.
    public var needsReverseShare: Bool { incoming == .accepted && outgoing == .none }

    /// Returns the next friendship or throws for a transition that cannot happen.
    public func applying(_ event: FriendshipEvent) throws -> Friendship {
        var next = self
        switch event {
        case .sentInvite:
            if outgoing == .none { next.outgoing = .invited }
        case .receivedInvite:
            if incoming == .none { next.incoming = .pending }
        case .theyAccepted:
            guard outgoing != .none else { throw FriendshipError.invalidTransition(from: state, event: event) }
            next.outgoing = .accepted
        case .iAccepted:
            guard incoming != .none else { throw FriendshipError.invalidTransition(from: state, event: event) }
            next.incoming = .accepted
        case .theyLeftMyShare:
            next.outgoing = .none
        case .theirShareEnded:
            next.incoming = .none
        case .iRemoved:
            next.outgoing = .none
            next.incoming = .none
        }
        return next
    }

    /// The `Friend` value that older call sites use. Only `mutual` and one-way friends count as accepted.
    public var asFriend: Friend {
        let accepted = outgoing == .accepted || incoming == .accepted
        return Friend(id: id, displayName: displayName, status: accepted ? .accepted : .invited)
    }
}

/// What CloudKit reports right now. The app builds this from my share's participants
/// and from the zones in the shared database.
public struct SharingSnapshot: Sendable, Hashable {
    public struct Participant: Sendable, Hashable {
        public var id: String
        public var displayName: String
        public var accepted: Bool

        public init(id: String, displayName: String, accepted: Bool) {
            self.id = id
            self.displayName = displayName
            self.accepted = accepted
        }
    }

    /// Participants of my share, without me.
    public var outgoing: [Participant]
    /// Owners of the zones in my shared database. A zone there means I accepted their share.
    public var incoming: [Participant]

    public init(outgoing: [Participant] = [], incoming: [Participant] = []) {
        self.outgoing = outgoing
        self.incoming = incoming
    }
}

/// All friendships of this user, with the friend cap.
public struct FriendRoster: Sendable, Hashable, Codable {
    /// Product cap. CloudKit allows 100 participants per share, so 50 leaves room.
    public static let defaultLimit = 50

    public private(set) var friendships: [Friendship]
    public var limit: Int

    public init(_ friendships: [Friendship] = [], limit: Int = FriendRoster.defaultLimit) {
        self.friendships = friendships
        self.limit = limit
    }

    public var active: [Friendship] { friendships.filter { $0.state.isActive } }
    public var activeCount: Int { active.count }
    public var canAddFriend: Bool { activeCount < limit }

    public subscript(id: String) -> Friendship? { friendships.first { $0.id == id } }

    /// Applies an event to one friend. A new active friend over the cap throws `friendLimitReached`.
    /// `displayName` updates the stored name when it is not empty.
    @discardableResult
    public mutating func apply(_ event: FriendshipEvent, to id: String, displayName: String = "") throws -> Friendship {
        let index = friendships.firstIndex { $0.id == id }
        let current = index.map { friendships[$0] } ?? Friendship(id: id, displayName: displayName)
        var next = try current.applying(event)
        if !displayName.isEmpty { next.displayName = displayName }

        if !current.state.isActive, next.state.isActive, !canAddFriend {
            throw FriendshipError.friendLimitReached(limit: limit)
        }
        if let index { friendships[index] = next } else { friendships.append(next) }
        return next
    }

    /// Makes the roster match CloudKit. CloudKit wins for accepted and invited sides.
    /// A local `pending` incoming side is kept, because CloudKit does not list unaccepted invites I received.
    /// Friends that CloudKit no longer reports become `removed`. They are kept so the UI can show history.
    /// Snapshot friends over the cap are still recorded, because CloudKit already holds them.
    public mutating func reconcile(with snapshot: SharingSnapshot) {
        var byID: [String: Friendship] = [:]
        var order: [String] = []
        for friendship in friendships {
            var f = friendship
            f.outgoing = .none
            if f.incoming == .accepted { f.incoming = .none }
            byID[f.id] = f
            order.append(f.id)
        }
        func upsert(_ id: String, _ name: String, _ change: (inout Friendship) -> Void) {
            var f = byID[id] ?? Friendship(id: id, displayName: name)
            if byID[id] == nil { order.append(id) }
            if !name.isEmpty { f.displayName = name }
            change(&f)
            byID[id] = f
        }
        for p in snapshot.outgoing {
            upsert(p.id, p.displayName) { $0.outgoing = p.accepted ? .accepted : .invited }
        }
        for p in snapshot.incoming {
            upsert(p.id, p.displayName) { $0.incoming = .accepted }
        }
        friendships = order.compactMap { byID[$0] }
    }

    /// Drops everything, for "Delete all data".
    public mutating func removeAll() { friendships.removeAll() }
}
