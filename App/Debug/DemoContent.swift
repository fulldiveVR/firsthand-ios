#if os(iOS) && DEBUG
import FirsthandCore
import Foundation
import UIKit

/// Fixed demo content for screenshots. Debug builds only. Nothing here touches PhotoKit or CloudKit.
///
/// Launch arguments:
/// - `-demoContent YES` fills the app with fixture friends, posts and a suggestion.
/// - `-demoState <suggestion|analyzing|quiet|shared|skipped|limited|failed>` picks the Today state.
/// - `-demoFriends <none|waiting|some>` picks the friend list. Default `some`.
/// - `-demoSheet <friends|profile>` opens that sheet on launch.
/// The fixture photos are abstract renders from `scripts/make-demo-fixtures.swift`.
enum DemoContent {
    enum State: String {
        case suggestion, analyzing, quiet, shared, skipped, limited, failed
    }

    enum Friends: String {
        case none, waiting, some
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "demoContent") }

    static var state: State {
        UserDefaults.standard.string(forKey: "demoState").flatMap(State.init(rawValue:)) ?? .suggestion
    }

    static var friendsMode: Friends {
        UserDefaults.standard.string(forKey: "demoFriends").flatMap(Friends.init(rawValue:)) ?? .some
    }

    static let assetPrefix = "demo:"
    static let placeBucket = "demo:lake"

    /// Demo asset ids are `demo:<asset catalog name>`.
    static func image(for assetID: String) -> UIImage? {
        guard assetID.hasPrefix(assetPrefix) else { return nil }
        return UIImage(named: String(assetID.dropFirst(assetPrefix.count)))
    }

    static var now: Date { Date() }

    /// That time today. If it is still in the future, one hour ago, so the moment stays "Today".
    static func todayAt(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let date = calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: start) ?? now
        return date <= now ? date : now.addingTimeInterval(-3600)
    }

    static var suggestion: Suggestion {
        Suggestion(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!,
            assetID: assetPrefix + "demo-lake",
            caption: String(localized: "Golden hour at the lake"),
            score: 0.82,
            provenance: .likelyCamera,
            sceneLabels: ["lake", "sky", "outdoor"],
            locationBucket: placeBucket,
            createdAt: todayAt(hour: 18, minute: 40).addingTimeInterval(20 * 60),
            reasons: [.newPlace, .withFriends, .scene("lake"), .today, .provenance(.likelyCamera)],
            captureDate: todayAt(hour: 18, minute: 40)
        )
    }

    static let placeNames = [placeBucket: "Lake Merritt"]

    static var friendships: [Friendship] {
        switch friendsMode {
        case .none:
            return []
        case .waiting:
            return [
                Friendship(id: "demo-sam", displayName: "Sam Rivera", outgoing: .invited),
                Friendship(id: "demo-noor", displayName: "Noor Haddad", incoming: .pending),
            ]
        case .some:
            return [
                Friendship(id: "demo-mia", displayName: "Mia Chen", outgoing: .accepted, incoming: .accepted),
                Friendship(id: "demo-leo", displayName: "Leo Novak", outgoing: .accepted, incoming: .accepted),
                Friendship(id: "demo-ana", displayName: "Ana Souza", outgoing: .accepted, incoming: .accepted),
                Friendship(id: "demo-jon", displayName: "Jon Park", outgoing: .accepted),
                Friendship(id: "demo-sam", displayName: "Sam Rivera", outgoing: .invited),
                Friendship(id: "demo-noor", displayName: "Noor Haddad", incoming: .pending),
            ]
        }
    }

    /// Friends' posts and my own posts. Images are written once to the caches folder.
    static var posts: [Post] {
        let hour: TimeInterval = 3600, day: TimeInterval = 86_400
        let own = CloudKitSharing.ownOwnerID
        var result: [Post] = []
        if friendsMode == .some {
            result += [
                post("demo-beach", "D101", author: "demo-mia", name: "Mia Chen", caption: "First swim of the season", age: 40 * 60),
                post("demo-park", "D102", author: "demo-leo", name: "Leo Novak", caption: "Lily's birthday in the park", age: 5 * hour),
                post("demo-city", "D103", author: "demo-ana", name: "Ana Souza", caption: "Late walk home", age: 1 * day + 3 * hour),
                post("demo-food", "D104", author: "demo-mia", name: "Mia Chen", caption: "Sunday lunch with everyone", age: 25 * day, provenance: .unknown),
            ]
        }
        result += [
            post("demo-mountain", "D201", author: own, name: String(localized: "You"), caption: "Top of the ridge", age: 2 * day),
            post("demo-forest", "D202", author: own, name: String(localized: "You"), caption: "Morning in the woods", age: 6 * day),
            post("demo-snow", "D203", author: own, name: String(localized: "You"), caption: "First snow", age: 19 * day),
            post("demo-park", "D204", author: own, name: String(localized: "You"), caption: "Kites and balloons", age: 26 * day),
        ]
        if state == .shared {
            result.append(post("demo-lake", "D001", author: own, name: String(localized: "You"), caption: suggestion.caption, age: now.timeIntervalSince(suggestion.createdAt) * 0.5))
        }
        return result
    }

    private static func post(
        _ asset: String, _ idSuffix: String, author: String, name: String, caption: String?, age: TimeInterval,
        provenance: ProvenanceStatus = .likelyCamera
    ) -> Post {
        Post(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000\(idSuffix)") ?? UUID(),
            authorID: author,
            authorName: name,
            caption: caption,
            provenance: provenance,
            createdAt: now.addingTimeInterval(-age),
            imageURL: imageFile(asset)
        )
    }

    private static func imageFile(_ asset: String) -> URL? {
        let dir = URL.cachesDirectory.appending(path: "demo-images")
        let url = dir.appending(path: "\(asset).jpg")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let data = UIImage(named: asset)?.jpegData(compressionQuality: 0.9) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url)
        return url
    }

    /// Applies the demo state to the model. Called once at launch.
    @MainActor
    static func apply(to model: AppModel) {
        model.isDemo = true
        if model.appleUserID == nil { model.appleUserID = "debug-user" }
        model.userName = "Alex Morgan"
        model.hasCompletedFirstScan = true
        model.photoAccess = .authorized
        model.notificationAccess = .allowed
        model.friendships = friendships
        model.friends = friendships.map(\.asFriend)
        model.feed = Post.visible(posts, now: now)
        model.placeNames = placeNames
        model.analyzedPhotoCount = 1_284

        model.homeSheet = UserDefaults.standard.string(forKey: "demoSheet").flatMap(AppModel.HomeSheet.init(rawValue:))

        switch state {
        case .suggestion:
            model.pending = suggestion
        case .analyzing:
            model.manualScan = .running(AnalysisProgress(completed: 37, total: 120, phase: .analyzing))
        case .quiet:
            break
        case .shared:
            var decided = suggestion
            decided.decision = .share
            model.decidedToday = decided
        case .skipped:
            var decided = suggestion
            decided.decision = .skip
            model.decidedToday = decided
        case .limited:
            model.photoAccess = .limited
        case .failed:
            model.manualScan = .finished(.failed)
        }
    }
}
#endif
