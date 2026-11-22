import Foundation
import Testing
@testable import CandidCore

private func post(_ n: Int, by owner: String, at offset: TimeInterval, caption: String? = nil) -> Post {
    Post(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
        authorID: owner,
        authorName: owner.uppercased(),
        caption: caption,
        provenance: .likelyCamera,
        createdAt: day0.addingTimeInterval(offset)
    )
}

@Suite struct FeedStateTests {
    @Test func sortsNewestFirst() {
        var feed = FeedState()
        feed.apply(FeedChanges(changed: [post(1, by: "a", at: 0), post(2, by: "b", at: 60), post(3, by: "a", at: 30)]))
        #expect(feed.posts.map(\.createdAt) == [day0 + 60, day0 + 30, day0])
    }

    @Test func dedupesByRecordIDAndKeepsTheLatestVersion() {
        var feed = FeedState([post(1, by: "a", at: 0, caption: "old")])
        feed.apply(FeedChanges(changed: [post(1, by: "a", at: 0, caption: "new"), post(1, by: "a", at: 0, caption: "newest")]))
        #expect(feed.count == 1)
        #expect(feed.posts.first?.caption == "newest")
    }

    @Test func sameRecordNameInTwoZonesIsTwoPosts() {
        let feed = FeedState([post(1, by: "a", at: 0), post(1, by: "b", at: 0)])
        #expect(feed.count == 2)
    }

    @Test func dropsDeletedRecords() {
        var feed = FeedState([post(1, by: "a", at: 0), post(2, by: "a", at: 10)])
        feed.apply(FeedChanges(deleted: [post(1, by: "a", at: 0).feedItemID]))
        #expect(feed.posts.map(\.feedItemID.recordName) == [post(2, by: "a", at: 0).id.uuidString])
    }

    @Test func deleteWinsOverChangeInOneBatch() {
        let p = post(1, by: "a", at: 0)
        let feed = FeedState().applying(FeedChanges(changed: [p], deleted: [p.feedItemID]))
        #expect(feed.count == 0)
    }

    @Test func deletingUnknownRecordIsHarmless() {
        var feed = FeedState([post(1, by: "a", at: 0)])
        feed.apply(FeedChanges(deleted: [FeedItemID(ownerID: "z", recordName: "nope")]))
        #expect(feed.count == 1)
    }

    @Test func removedOwnerLosesAllPostsAndCannotBeReAddedInSameBatch() {
        var feed = FeedState([post(1, by: "a", at: 0), post(2, by: "b", at: 0)])
        feed.apply(FeedChanges(changed: [post(3, by: "a", at: 5)], removedOwners: ["a"]))
        #expect(feed.posts.map(\.authorID) == ["b"])
    }

    @Test func resetOwnerIsReplacedByTheRefetch() {
        var feed = FeedState([post(1, by: "a", at: 0), post(2, by: "a", at: 1), post(9, by: "b", at: 0)])
        feed.apply(FeedChanges(changed: [post(2, by: "a", at: 1)], resetOwners: ["a"]))
        #expect(feed.posts(by: "a").count == 1)
        #expect(feed.posts(by: "b").count == 1)
    }

    @Test func roundTripsThroughJSON() throws {
        let feed = FeedState([post(1, by: "a", at: 0), post(2, by: "b", at: 5)])
        let data = try JSONEncoder().encode(feed)
        #expect(try JSONDecoder().decode(FeedState.self, from: data) == feed)
    }

    @Test func mapsImageURLs() {
        var p = post(1, by: "a", at: 0)
        p.imageURL = URL(fileURLWithPath: "/old/container/a.heic")
        var feed = FeedState([p])
        feed.mapImageURLs { URL(fileURLWithPath: "/new/" + $0.lastPathComponent) }
        #expect(feed.posts.first?.imageURL?.path == "/new/a.heic")
    }
}

@Suite struct ChangeTokenStoreTests {
    let zoneA = ChangeTokenKey.zone(ownerName: "_a", zoneName: "Posts")
    let zoneB = ChangeTokenKey.zone(ownerName: "_b", zoneName: "Posts")

    @Test func keysAreDistinct() {
        #expect(Set([ChangeTokenKey.sharedDatabase.storageKey, zoneA.storageKey, zoneB.storageKey]).count == 3)
    }

    @Test func inMemoryStoreSetsReadsAndRemoves() async throws {
        let store = InMemoryChangeTokenStore()
        try await store.setToken(Data([1]), for: .sharedDatabase)
        try await store.setToken(Data([2]), for: zoneA)
        try await store.setToken(Data([3]), for: zoneB)
        #expect(await store.token(for: zoneA) == Data([2]))
        try await store.removeTokens(ownerName: "_a")
        #expect(await store.token(for: zoneA) == nil)
        #expect(await store.token(for: zoneB) == Data([3]))
        try await store.setToken(nil, for: zoneB)
        #expect(await store.token(for: zoneB) == nil)
        try await store.removeAll()
        #expect(await store.token(for: .sharedDatabase) == nil)
    }

    @Test func fileStorePersistsAcrossInstances() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tokens-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "tokens.json")

        let first = FileChangeTokenStore(url: url)
        #expect(await first.token(for: .sharedDatabase) == nil)
        try await first.setToken(Data([7, 7]), for: .sharedDatabase)
        try await first.setToken(Data([8]), for: zoneA)

        let second = FileChangeTokenStore(url: url)
        #expect(await second.token(for: .sharedDatabase) == Data([7, 7]))
        try await second.removeTokens(ownerName: "_a")

        let third = FileChangeTokenStore(url: url)
        #expect(await third.token(for: zoneA) == nil)
        try await third.removeAll()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await FileChangeTokenStore(url: url).token(for: .sharedDatabase) == nil)
    }

    @Test func brokenFileMeansNoTokens() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tokens-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "tokens.json")
        try Data("not json".utf8).write(to: url)
        let store = FileChangeTokenStore(url: url)
        #expect(await store.token(for: .sharedDatabase) == nil)
        try await store.setToken(Data([1]), for: .sharedDatabase)
        #expect(await FileChangeTokenStore(url: url).token(for: .sharedDatabase) == Data([1]))
    }
}

@Suite struct PostPayloadRulesTests {
    typealias Size = PostPayloadRules.PixelSize

    @Test func landscapeIsScaledToLongEdge() {
        #expect(PostPayloadRules.targetSize(for: Size(width: 4032, height: 3024)) == Size(width: 2048, height: 1536))
    }

    @Test func portraitIsScaledToLongEdge() {
        #expect(PostPayloadRules.targetSize(for: Size(width: 3024, height: 4032)) == Size(width: 1536, height: 2048))
    }

    @Test func squareAndPanorama() {
        #expect(PostPayloadRules.targetSize(for: Size(width: 5000, height: 5000)) == Size(width: 2048, height: 2048))
        #expect(PostPayloadRules.targetSize(for: Size(width: 16000, height: 4)) == Size(width: 2048, height: 1))
    }

    @Test func smallImagesAreNotUpscaled() {
        #expect(PostPayloadRules.targetSize(for: Size(width: 1200, height: 800)) == Size(width: 1200, height: 800))
        #expect(PostPayloadRules.targetSize(for: Size(width: 2048, height: 10)) == Size(width: 2048, height: 10))
    }

    @Test func invalidSizeGivesZero() {
        #expect(PostPayloadRules.targetSize(for: Size(width: 0, height: 100)) == Size(width: 0, height: 0))
    }

    @Test func encodingPrefersHEIC() {
        #expect(PostPayloadRules.encoding(heicAvailable: true) == .heic)
        #expect(PostPayloadRules.encoding(heicAvailable: false) == .jpeg)
        #expect(PostPayloadRules.Encoding.jpeg.fileExtension == "jpg")
    }

    @Test func stripsLocationAndSerialsButKeepsCameraHints() {
        let input: [String: Any] = [
            "{GPS}": ["Latitude": 52.1, "Longitude": 4.3],
            "{IPTC}": ["City": "Somewhere"],
            "{MakerApple}": ["1": 2],
            "{ExifAux}": ["SerialNumber": "x"],
            "{Exif}": ["ExposureTime": 0.01, "BodySerialNumber": "123", "LensSerialNumber": "456", "DateTimeOriginal": "2026:01:01 10:00:00"],
            "{TIFF}": ["Make": "Apple", "Model": "iPhone", "HostComputer": "x", "Orientation": 6],
            "Orientation": 6,
            "PixelWidth": 4032,
        ]
        let out = PostPayloadRules.sanitizedProperties(input)
        #expect(!PostPayloadRules.containsLocation(out))
        #expect(PostPayloadRules.containsLocation(input))
        #expect(out["{ExifAux}"] == nil)
        let exif = out["{Exif}"] as? [String: Any]
        #expect(exif?["ExposureTime"] as? Double == 0.01)
        #expect(exif?["DateTimeOriginal"] != nil)
        #expect(exif?["BodySerialNumber"] == nil)
        #expect(exif?["LensSerialNumber"] == nil)
        let tiff = out["{TIFF}"] as? [String: Any]
        #expect(tiff?["Make"] as? String == "Apple")
        #expect(tiff?["HostComputer"] == nil)
        #expect(tiff?["Orientation"] as? Int == 1)
        #expect(out["Orientation"] as? Int == 1)
        #expect(out["PixelWidth"] as? Int == 4032)
    }

    @Test func captionIsTrimmedCappedOrDropped() {
        #expect(PostPayloadRules.normalizedCaption(nil) == nil)
        #expect(PostPayloadRules.normalizedCaption("  \n ") == nil)
        #expect(PostPayloadRules.normalizedCaption("  Beach day ") == "Beach day")
        let long = String(repeating: "a", count: 400)
        #expect(PostPayloadRules.normalizedCaption(long)?.count == PostPayloadRules.maxCaptionLength)
    }

    @Test func provenanceLabelsNeverSayVerified() throws {
        #expect(try PostPayloadRules.provenanceLabel(for: .likelyCamera) == "likelyCamera")
        #expect(try PostPayloadRules.provenanceLabel(for: .unknown) == "unknown")
        #expect(try PostPayloadRules.provenanceLabel(for: .hasReferenceImageData) == "hasReferenceImageData")
        #expect(throws: PostPayloadRules.PayloadError.notShareable) {
            try PostPayloadRules.provenanceLabel(for: .excluded)
        }
        for status in ProvenanceStatus.allCases where status.isShareable {
            #expect(try !PostPayloadRules.provenanceLabel(for: status).lowercased().contains("verified"))
        }
    }

    @Test func remoteLabelsFallBackToUnknown() {
        #expect(PostPayloadRules.provenance(fromLabel: "likelyCamera") == .likelyCamera)
        #expect(PostPayloadRules.provenance(fromLabel: "verified") == .unknown)
        #expect(PostPayloadRules.provenance(fromLabel: "excluded") == .unknown)
        #expect(PostPayloadRules.provenance(fromLabel: nil) == .unknown)
    }

    @Test func zoneIsNotTheDefaultZone() {
        #expect(PostRecordSchema.zoneName == "Posts")
        #expect(PostRecordSchema.zoneName != "_defaultZone")
    }
}

@Suite struct InMemoryShareServiceSharingTests {
    @Test func deletePostAndDeleteAll() async throws {
        let incoming = [post(1, by: "a", at: 0)]
        let service = InMemoryShareService(author: Friend(id: "me", displayName: "Me"), incoming: incoming, clock: FixedClock(day0))
        let s = Suggestion(assetID: "x", score: 1, provenance: .likelyCamera, createdAt: day0)
        let p = try await service.share(s, imageData: Data(), with: ["a"])
        #expect(await service.myPosts().map(\.id) == [p.id])
        try await service.deletePost(p.id)
        #expect(await service.myPosts().isEmpty)
        try await service.deleteAllData()
        #expect(await service.feed().isEmpty)
    }
}
