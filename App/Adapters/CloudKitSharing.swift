#if os(iOS)
import CandidCore
import CloudKit
import Foundation

/// All CloudKit sharing state of this user. Apple hosts the data, there is no own photo server.
///
/// Model:
/// - My posts live in one custom zone `Posts` in my private database. The default zone cannot be shared.
/// - One zone-wide `CKShare` with `publicPermission = .none`. Friends are its read-only participants.
/// - Friends' zones appear in my shared database after I accept their share.
/// - A friend's id is their CloudKit user record name. It is also the owner name of their zone.
actor CloudKitSharing {
    enum SharingError: Error {
        case shareHasNoURL
        case participantNotFound
        case wrongContainer
        case ownShare
        case unknownOwner
    }

    nonisolated let container: CKContainer
    private let tokens: any ChangeTokenStore
    private let rosterURL: URL
    private let feedURL: URL
    private let myPostsURL: URL
    private let imageCache: URL

    private var zoneReady = false
    private var roster: FriendRoster?
    private var feedState: FeedState?
    private var myPostsState: FeedState?

    static let ownOwnerID = CKCurrentUserDefaultName
    nonisolated var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: PostRecordSchema.zoneName, ownerName: CKCurrentUserDefaultName)
    }
    nonisolated var shareID: CKRecord.ID { CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID) }

    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    init(
        container: CKContainer = CKContainer(identifier: AppInfo.cloudKitContainerID),
        tokens: any ChangeTokenStore = FileChangeTokenStore(url: AppInfo.dataDirectory.appending(path: "change-tokens.json")),
        directory: URL = AppInfo.dataDirectory,
        imageCache: URL = URL.cachesDirectory.appending(path: "feed-images")
    ) {
        self.container = container
        self.tokens = tokens
        rosterURL = directory.appending(path: "friends.json")
        feedURL = directory.appending(path: "feed.json")
        myPostsURL = directory.appending(path: "my-posts.json")
        self.imageCache = imageCache
    }

    // MARK: Zone and share

    func ensureZone() async throws {
        guard !zoneReady else { return }
        // Saving an existing zone is a no-op on the server.
        _ = try await privateDB.save(CKRecordZone(zoneID: zoneID))
        zoneReady = true
    }

    /// My zone-wide share, or `nil` when it does not exist yet.
    func currentShare() async throws -> CKShare? {
        do {
            return try await privateDB.record(for: shareID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    func ensureShare() async throws -> CKShare {
        try await ensureZone()
        if let share = try await currentShare() { return share }
        let share = CKShare(recordZoneID: zoneID)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = String(localized: "\(AppInfo.name) moments")
        do {
            return try await save(share)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Another device created it first.
            if let share = try await currentShare() { return share }
            throw error
        }
    }

    private func save(_ share: CKShare) async throws -> CKShare {
        let result = try await privateDB.modifyRecords(saving: [share], deleting: [])
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw CKError(.internalError)
        }
        return saved
    }

    /// Applies a change to my share and saves it. Refetches and retries once on a conflict.
    private func modifyShare(_ change: (CKShare) throws -> Void) async throws -> CKShare {
        var share = try await ensureShare()
        for attempt in 0..<2 {
            try change(share)
            do {
                return try await save(share)
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                guard let fresh = try await currentShare() else { throw error }
                share = fresh
            }
        }
        throw CKError(.serverRecordChanged)
    }

    /// Friends that hold a slot in my share. Unclaimed one-time invite links are not friends yet.
    private func friendParticipants(_ share: CKShare) -> [CKShare.Participant] {
        share.participants.filter { $0.role != .owner && !Self.isUnclaimedOneTimeInvite($0) }
    }

    private static func isUnclaimedOneTimeInvite(_ p: CKShare.Participant) -> Bool {
        p.acceptanceStatus == .pending && p.userIdentity.userRecordID == nil && p.userIdentity.lookupInfo == nil
    }

    private func checkCap(_ share: CKShare) throws {
        if friendParticipants(share).count >= FriendRoster.defaultLimit {
            throw FriendshipError.friendLimitReached(limit: FriendRoster.defaultLimit)
        }
    }

    /// Checked by the Messages invite before the system adds a participant.
    func shareForSystemInvite() async throws -> CKShare {
        let share = try await ensureShare()
        try checkCap(share)
        return share
    }

    /// The plain share URL. It opens only for people who are participants already.
    func shareURL() async throws -> URL {
        guard let url = try await ensureShare().url else { throw SharingError.shareHasNoURL }
        return url
    }

    /// An invite link that any one person can claim. Used for QR codes and AirDrop.
    /// Reuses an unclaimed link, so open invites never pile up in the share.
    func oneTimeInviteURL() async throws -> URL {
        guard #available(iOS 26.0, *) else { return try await shareURL() }
        var share = try await ensureShare()
        if let open = share.participants.first(where: Self.isUnclaimedOneTimeInvite),
           let url = share.oneTimeURL(for: open.participantID) {
            return url
        }
        try checkCap(share)
        let participant = CKShare.Participant.oneTimeURLParticipant()
        participant.permission = .readOnly
        share = try await modifyShare { $0.addParticipant(participant) }
        guard let url = share.oneTimeURL(for: participant.participantID) else { throw SharingError.shareHasNoURL }
        return url
    }

    enum Lookup {
        case email(String)
        case phone(String)
        case userRecordName(String)
    }

    private func participant(for lookup: Lookup) async throws -> CKShare.Participant {
        let result: Result<CKShare.Participant, any Error>?
        switch lookup {
        case .email(let address):
            result = try await container.shareParticipants(forEmailAddresses: [address])[address]
        case .phone(let number):
            result = try await container.shareParticipants(forPhoneNumbers: [number])[number]
        case .userRecordName(let name):
            let id = CKRecord.ID(recordName: name)
            result = try await container.shareParticipants(forUserRecordIDs: [id])[id]
        }
        guard let participant = try result?.get() else { throw SharingError.participantNotFound }
        return participant
    }

    /// Adds a known person to my share and returns the link to send them.
    func addParticipant(_ lookup: Lookup, displayName: String = "") async throws -> URL {
        let participant = try await participant(for: lookup)
        let friendID = Self.friendID(of: participant)
        participant.permission = .readOnly
        var roster = loadRoster()
        if roster[friendID]?.state.isActive != true, !roster.canAddFriend {
            throw FriendshipError.friendLimitReached(limit: roster.limit)
        }

        let share = try await modifyShare { share in
            let already = share.participants.contains { Self.friendID(of: $0) == friendID }
            guard !already else { return }
            try checkCap(share)
            share.addParticipant(participant)
        }
        roster = loadRoster()
        try roster.apply(.sentInvite, to: friendID, displayName: displayName.isEmpty ? Self.name(of: participant.userIdentity) : displayName)
        try saveRoster(roster)
        guard let url = share.url else { throw SharingError.shareHasNoURL }
        return url
    }

    func invite(_ contact: InviteContact) async throws -> URL {
        switch contact {
        case .email(let address): try await addParticipant(.email(address))
        case .phone(let number): try await addParticipant(.phone(number))
        }
    }

    /// Reverse share: the friend whose share I accepted becomes a participant of mine.
    func shareBack(with friendID: String) async throws -> URL {
        let name = loadRoster()[friendID]?.displayName ?? ""
        return try await addParticipant(.userRecordName(friendID), displayName: name)
    }

    // MARK: Accept

    /// Accepts a friend's share after the user opened its link.
    func accept(_ metadata: CKShare.Metadata) async throws -> Friendship {
        guard metadata.containerIdentifier == container.containerIdentifier else { throw SharingError.wrongContainer }
        guard metadata.participantRole != .owner else { throw SharingError.ownShare }
        let owner = metadata.share.owner.userIdentity
        guard let ownerID = owner.userRecordID?.recordName else { throw SharingError.unknownOwner }
        let name = Self.name(of: owner)

        var roster = loadRoster()
        try roster.apply(.receivedInvite, to: ownerID, displayName: name)
        try saveRoster(roster)

        if metadata.participantStatus != .accepted {
            _ = try await container.accept(metadata)
        }
        let friendship = try roster.apply(.iAccepted, to: ownerID, displayName: name)
        try saveRoster(roster)
        return friendship
    }

    // MARK: Friends

    /// Reads both sides from CloudKit and updates the local roster.
    func friendships() async throws -> [Friendship] {
        var roster = loadRoster()
        roster.reconcile(with: try await snapshot())
        try saveRoster(roster)
        return roster.friendships
    }

    private func snapshot() async throws -> SharingSnapshot {
        var outgoing: [SharingSnapshot.Participant] = []
        if let share = try await currentShare() {
            outgoing = friendParticipants(share).map {
                .init(id: Self.friendID(of: $0), displayName: Self.name(of: $0.userIdentity), accepted: $0.acceptanceStatus == .accepted)
            }
        }
        let zones = try await sharedDB.allRecordZones().filter { $0.zoneID.zoneName == PostRecordSchema.zoneName }
        let shareIDs = zones.map { CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: $0.zoneID) }
        let shares = shareIDs.isEmpty ? [:] : try await sharedDB.records(for: shareIDs)
        let incoming: [SharingSnapshot.Participant] = zones.map { zone in
            let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone.zoneID)
            let share = (try? shares[id]?.get()) as? CKShare
            return .init(id: zone.zoneID.ownerName, displayName: share.map { Self.name(of: $0.owner.userIdentity) } ?? "", accepted: true)
        }
        return SharingSnapshot(outgoing: outgoing, incoming: incoming)
    }

    /// Removes the friend from my share and leaves their share. Both directions end.
    func remove(_ friendID: String) async throws {
        if let share = try await currentShare(), share.participants.contains(where: { Self.friendID(of: $0) == friendID }) {
            _ = try await modifyShare { share in
                for p in share.participants where Self.friendID(of: p) == friendID {
                    share.removeParticipant(p)
                }
            }
        }
        try await leaveShare(ownerID: friendID)

        var roster = loadRoster()
        if roster[friendID] != nil { try roster.apply(.iRemoved, to: friendID) }
        try saveRoster(roster)
    }

    /// A participant that deletes the share record leaves the share. The zone then leaves the shared database.
    private func leaveShare(ownerID: String) async throws {
        let zone = CKRecordZone.ID(zoneName: PostRecordSchema.zoneName, ownerName: ownerID)
        do {
            _ = try await sharedDB.deleteRecord(withID: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone))
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // Not a participant, or already left.
        }
        var feed = loadFeed()
        feed.apply(FeedChanges(removedOwners: [ownerID]))
        try saveFeed(feed)
        try await tokens.removeTokens(ownerName: ownerID)
    }

    // MARK: Posts

    func publish(caption: String?, provenance: ProvenanceStatus, imageData: Data) async throws -> Post {
        let label = try PostPayloadRules.provenanceLabel(for: provenance)
        _ = try await ensureShare()
        let file = try PostImageEncoder.encode(imageData)
        defer { try? FileManager.default.removeItem(at: file) }

        let post = Post(
            authorID: Self.ownOwnerID,
            authorName: String(localized: "You"),
            caption: PostPayloadRules.normalizedCaption(caption),
            provenance: provenance,
            createdAt: Date()
        )
        let record = CKRecord(
            recordType: PostRecordSchema.recordType,
            recordID: CKRecord.ID(recordName: post.id.uuidString, zoneID: zoneID)
        )
        record[PostRecordSchema.image] = CKAsset(fileURL: file)
        record[PostRecordSchema.caption] = post.caption
        record[PostRecordSchema.createdAt] = post.createdAt
        record[PostRecordSchema.provenance] = label
        let saved = try await privateDB.save(record)

        var mine = loadMyPosts()
        mine.apply(FeedChanges(changed: [makePost(saved, ownerID: Self.ownOwnerID, authorName: post.authorName) ?? post]))
        try saveMyPosts(mine)
        return post
    }

    func deletePost(_ id: UUID) async throws {
        do {
            _ = try await privateDB.deleteRecord(withID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID))
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone.
        }
        var mine = loadMyPosts()
        mine.apply(FeedChanges(deleted: [FeedItemID(ownerID: Self.ownOwnerID, recordName: id.uuidString)]))
        try saveMyPosts(mine)
    }

    // MARK: Sync

    /// Friends' posts. Uses database changes, then record zone changes per changed zone.
    func syncFeed() async throws -> [Post] {
        var feed = loadFeed()
        var dbToken = Self.unarchive(await tokens.token(for: .sharedDatabase))
        var changedZones: [CKRecordZone.ID] = []
        var removedOwners: Set<String> = []
        var more = true
        while more {
            let result: (modifications: [CKDatabase.DatabaseChange.Modification], deletions: [CKDatabase.DatabaseChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool)
            do {
                result = try await sharedDB.databaseChanges(since: dbToken)
            } catch let error as CKError where error.code == .changeTokenExpired && dbToken != nil {
                dbToken = nil
                continue
            }
            changedZones += result.modifications.map(\.zoneID)
            removedOwners.formUnion(result.deletions.map(\.zoneID.ownerName))
            dbToken = result.changeToken
            more = result.moreComing
        }

        var zoneTokens: [(ChangeTokenKey, Data?)] = []
        var seen: Set<CKRecordZone.ID> = []
        for zone in changedZones where zone.zoneName == PostRecordSchema.zoneName && !removedOwners.contains(zone.ownerName) {
            guard seen.insert(zone).inserted else { continue }
            let name = loadRoster()[zone.ownerName]?.displayName ?? String(localized: "A friend")
            let (changes, token) = try await zoneChanges(in: sharedDB, zone: zone, ownerID: zone.ownerName, authorName: name)
            feed.apply(changes)
            zoneTokens.append((.zone(ownerName: zone.ownerName, zoneName: zone.zoneName), token))
        }
        feed.apply(FeedChanges(removedOwners: removedOwners))

        // Save the feed before the tokens, so a crash refetches instead of losing posts.
        try saveFeed(feed)
        for owner in removedOwners { try await tokens.removeTokens(ownerName: owner) }
        for (key, token) in zoneTokens { try await tokens.setToken(token, for: key) }
        try await tokens.setToken(Self.archive(dbToken), for: .sharedDatabase)
        return feed.posts
    }

    /// My own posts, from my private zone.
    func syncMyPosts() async throws -> [Post] {
        var mine = loadMyPosts()
        do {
            let (changes, token) = try await zoneChanges(
                in: privateDB, zone: zoneID, ownerID: Self.ownOwnerID, authorName: String(localized: "You")
            )
            mine.apply(changes)
            try saveMyPosts(mine)
            try await tokens.setToken(token, for: .zone(ownerName: Self.ownOwnerID, zoneName: zoneID.zoneName))
        } catch let error as CKError where error.code == .zoneNotFound {
            mine = FeedState()
            try saveMyPosts(mine)
        }
        return mine.posts
    }

    private func zoneChanges(
        in db: CKDatabase, zone: CKRecordZone.ID, ownerID: String, authorName: String
    ) async throws -> (FeedChanges, Data?) {
        let key = ChangeTokenKey.zone(ownerName: ownerID, zoneName: zone.zoneName)
        var token = Self.unarchive(await tokens.token(for: key))
        var changes = FeedChanges()
        var more = true
        while more {
            let result: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>], deletions: [CKDatabase.RecordZoneChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool)
            do {
                result = try await db.recordZoneChanges(inZoneWith: zone, since: token)
            } catch let error as CKError where error.code == .changeTokenExpired && token != nil {
                token = nil
                changes = FeedChanges(resetOwners: [ownerID])
                continue
            }
            for (_, modification) in result.modificationResultsByID {
                guard let record = try? modification.get().record,
                      let post = makePost(record, ownerID: ownerID, authorName: authorName)
                else { continue }
                changes.changed.append(post)
            }
            for deletion in result.deletions where deletion.recordType == PostRecordSchema.recordType {
                changes.deleted.append(FeedItemID(ownerID: ownerID, recordName: deletion.recordID.recordName))
            }
            token = result.changeToken
            more = result.moreComing
        }
        return (changes, Self.archive(token))
    }

    /// Skips the share record and anything that is not a valid post. Copies the image into the cache.
    private func makePost(_ record: CKRecord, ownerID: String, authorName: String) -> Post? {
        guard record.recordType == PostRecordSchema.recordType,
              let id = UUID(uuidString: record.recordID.recordName)
        else { return nil }
        var imageURL: URL?
        if let asset = record[PostRecordSchema.image] as? CKAsset, let source = asset.fileURL {
            let target = imageCache.appending(path: "\(ownerID)-\(id.uuidString).img")
            try? FileManager.default.createDirectory(at: imageCache, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            if (try? FileManager.default.copyItem(at: source, to: target)) != nil { imageURL = target }
        }
        return Post(
            id: id,
            authorID: ownerID,
            authorName: authorName,
            caption: PostPayloadRules.normalizedCaption(record[PostRecordSchema.caption] as? String),
            provenance: PostPayloadRules.provenance(fromLabel: record[PostRecordSchema.provenance] as? String),
            createdAt: record[PostRecordSchema.createdAt] as? Date ?? record.creationDate ?? .distantPast,
            imageURL: imageURL
        )
    }

    // MARK: Delete all

    /// Deletes my zone (with its share and posts), leaves every friend's share, and clears local state.
    func deleteAll() async throws {
        do {
            _ = try await privateDB.deleteRecordZone(withID: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
            // Nothing published yet.
        }
        zoneReady = false
        for zone in (try? await sharedDB.allRecordZones()) ?? [] {
            try? await leaveShare(ownerID: zone.zoneID.ownerName)
        }
        try await tokens.removeAll()
        roster = FriendRoster()
        feedState = FeedState()
        myPostsState = FeedState()
        for url in [rosterURL, feedURL, myPostsURL, imageCache] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func resetRoster() throws {
        roster = FriendRoster()
        try? FileManager.default.removeItem(at: rosterURL)
    }

    // MARK: Local files

    private func loadRoster() -> FriendRoster {
        if let roster { return roster }
        let loaded: FriendRoster = Self.read(rosterURL) ?? FriendRoster()
        roster = loaded
        return loaded
    }

    private func saveRoster(_ value: FriendRoster) throws {
        roster = value
        try Self.write(value, to: rosterURL)
    }

    private func loadFeed() -> FeedState {
        if let feedState { return feedState }
        var loaded: FeedState = Self.read(feedURL) ?? FeedState()
        relinkImages(&loaded)
        feedState = loaded
        return loaded
    }

    private func saveFeed(_ value: FeedState) throws {
        feedState = value
        try Self.write(value, to: feedURL)
    }

    private func loadMyPosts() -> FeedState {
        if let myPostsState { return myPostsState }
        var loaded: FeedState = Self.read(myPostsURL) ?? FeedState()
        relinkImages(&loaded)
        myPostsState = loaded
        return loaded
    }

    private func saveMyPosts(_ value: FeedState) throws {
        myPostsState = value
        try Self.write(value, to: myPostsURL)
    }

    /// The app container path can change between launches. Images keep their file name.
    private func relinkImages(_ state: inout FeedState) {
        let cache = imageCache
        state.mapImageURLs { url in
            let local = cache.appending(path: url.lastPathComponent)
            return FileManager.default.fileExists(atPath: local.path) ? local : nil
        }
    }

    private static func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Helpers

    static func friendID(of participant: CKShare.Participant) -> String {
        participant.userIdentity.userRecordID?.recordName ?? "participant:\(participant.participantID)"
    }

    static func name(of identity: CKUserIdentity) -> String {
        guard let components = identity.nameComponents else { return "" }
        return PersonNameComponentsFormatter.localizedString(from: components, style: .default)
    }

    static func archive(_ token: CKServerChangeToken?) -> Data? {
        token.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
    }

    static func unarchive(_ data: Data?) -> CKServerChangeToken? {
        data.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
    }
}
#endif
