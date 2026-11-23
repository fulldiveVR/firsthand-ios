#if os(iOS)
import FirsthandCore
import CloudKit
import Foundation
import Observation
import Synchronization
import UIKit

@MainActor
@Observable
final class AppModel {
    enum ShareState: Equatable {
        case idle
        case working
        case failed(String)
    }

    enum FirstScanState: Equatable {
        case notStarted
        case scanning(AnalysisProgress)
    }

    /// "Find moments now": a foreground analysis pass that the user starts from Today or Settings.
    enum ManualScanState: Equatable {
        case idle
        case running(AnalysisProgress)
        case finished(ManualScanResult)
    }

    enum ManualScanResult: Equatable {
        case foundMoment
        case nothingYet
        case stopped
        case busy
        case needsFullAccess
        case failed
    }

    enum NotificationAccess: Equatable {
        case notDetermined
        case allowed
        case denied
    }

    /// Sheets on top of the Moments home screen.
    enum HomeSheet: String, Identifiable {
        case friends, profile
        var id: String { rawValue }
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
    /// Counts successful shares, for the success haptic.
    var shareSuccessCount = 0
    var firstScan: FirstScanState = .notStarted
    var manualScan: ManualScanState = .idle
    var notificationAccess: NotificationAccess = .notDetermined
    var homeSheet: HomeSheet?
    /// The name from Sign in with Apple, shown on the profile. Friends see the CloudKit name.
    var userName: String? {
        didSet { UserDefaults.standard.set(userName, forKey: Self.userNameKey) }
    }
    private var manualScanTask: Task<Void, Never>?
    private var manualScanStop: StopSignal?
    private var didCleanUpExpiredPosts = false
    var hasCompletedFirstScan: Bool {
        didSet { UserDefaults.standard.set(hasCompletedFirstScan, forKey: Self.firstScanKey) }
    }
    /// A friend to highlight in the Friends sheet, after an invite was accepted.
    var highlightedFriendID: String?
    /// A link to send, shown in a sheet with a QR code.
    var outgoingInvite: OutgoingInvite?
    var sharingError: String?
    /// Today's suggestion after the user shared or skipped it. Today then shows the decided state.
    var decidedToday: Suggestion?
    /// Reverse-geocoded names of coarse location buckets, for "Near ..." copy.
    var placeNames: [String: String] = [:]
    /// Photos with a stored analysis result, for the privacy stats.
    var analyzedPhotoCount = 0
    /// Debug demo content is on. Real services are not read.
    var isDemo = false

    struct OutgoingInvite: Identifiable, Equatable {
        var id: URL { url }
        var url: URL
        var friendName: String?
    }

    private static let userKey = "appleUserID"
    private static let firstScanKey = "hasCompletedFirstScan"
    private static let userNameKey = "userName"

    init(services: AppServices) {
        self.services = services
        appleUserID = UserDefaults.standard.string(forKey: Self.userKey)
        userName = UserDefaults.standard.string(forKey: Self.userNameKey)
        hasCompletedFirstScan = UserDefaults.standard.bool(forKey: Self.firstScanKey)
        #if DEBUG
        applyDebugLaunchArguments()
        #endif
    }

    var isOnboarded: Bool { appleUserID != nil && photoAccess.canRead && hasCompletedFirstScan }

    func refresh() async {
        if isDemo { return }
        photoAccess = await services.library.authorizationStatus()
        notificationAccess = await services.notifier.access()
        if photoAccess.canRead { services.startObservingLibrary() }
        analyzedPhotoCount = (try? await services.analysisCache.records().count) ?? analyzedPhotoCount
        let history = await services.history.load()
        pending = history.pending
        decidedToday = Self.decidedToday(in: history)
        // The 30-day rule, owner side. Once per launch, before the feed loads.
        if isOnboarded && !didCleanUpExpiredPosts {
            didCleanUpExpiredPosts = true
            await services.deleteExpiredPosts()
        }
        await refreshSharing()
    }

    /// The last suggestion made today that the user shared or skipped.
    static func decidedToday(in history: SuggestionHistory, now: Date = Date()) -> Suggestion? {
        history.suggestions.last { $0.decision != nil && Calendar.current.isDate($0.createdAt, inSameDayAs: now) }
    }

    /// The suggestion photo. Demo assets come from the debug asset catalog.
    func image(for assetID: String, side: CGFloat) async -> UIImage? {
        #if DEBUG
        if let demo = DemoContent.image(for: assetID) { return demo }
        #endif
        return await services.library.thumbnail(for: assetID, side: side)
    }

    /// Feed posts that are not expired at `now`. The feed view reads this, so a post never shows after 30 days.
    func visibleFeed(now: Date = Date()) -> [Post] { Post.visible(feed, now: now) }

    /// Friends from CloudKit, then friends' posts and my posts.
    func refreshSharing() async {
        if isDemo { return }
        if let list = try? await services.friends.friendships() {
            friendships = list.filter(\.state.isActive)
            friends = friendships.map(\.asFriend)
        }
        let theirs = (try? await services.shareService.feed()) ?? feed.filter { $0.authorID != CloudKitSharing.ownOwnerID }
        let mine = (try? await services.shareService.myPosts()) ?? feed.filter { $0.authorID == CloudKitSharing.ownOwnerID }
        feed = Post.visible(theirs + mine, now: Date())
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
            highlightedFriendID = current.id
            homeSheet = .friends
            // Finish the friendship in the same flow: share back so they see my moments too.
            // If this fails, the Friends sheet shows "Finish adding" for this friend.
            if current.needsReverseShare { await shareBack(with: current) }
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

    /// Only the Photos page in onboarding calls this, from its button.
    func requestPhotoAccess() async {
        photoAccess = await services.library.requestAuthorization()
        if photoAccess.canRead { services.startObservingLibrary() }
        AnalysisScheduler.schedule()
    }

    /// Only the Notifications page in onboarding calls this, from its button.
    func requestNotificationAccess() async {
        _ = await services.notifier.requestAuthorization()
        notificationAccess = await services.notifier.access()
    }

    var hasFriends: Bool { !friendships.isEmpty }

    /// The user taps "Find my moments". The scan continues if the user leaves the app.
    func startFirstScan() {
        guard firstScan == .notStarted else { return }
        // Limited access has nothing new to scan. Finish onboarding into the degraded mode.
        guard photoAccess == .authorized else {
            hasCompletedFirstScan = true
            return
        }
        firstScan = .scanning(AnalysisProgress(completed: 0, total: 0, phase: .scanning))
        AnalysisScheduler.startFirstScan(services: services) { [weak self] event in
            Task { @MainActor in self?.apply(event) }
        }
    }

    private func apply(_ event: AnalysisScheduler.FirstScanEvent) {
        switch event {
        case .progress(let p):
            guard firstScan != .notStarted else { return }
            firstScan = .scanning(p)
        case .finished(let suggestion, _):
            // An unfinished scan continues in the charging task. Onboarding ends either way.
            if let suggestion { pending = suggestion }
            firstScan = .notStarted
            hasCompletedFirstScan = true
        }
    }

    /// Share needs Face ID or Touch ID every time. Only approved friends receive the photo.
    /// Returns `true` when the moment was shared.
    @discardableResult
    func share() async -> Bool {
        guard let suggestion = pending else { return false }
        shareState = .working
        do {
            guard try await gate.confirmShare() else {
                shareState = .idle
                return false
            }
            if !isDemo {
                guard let data = try await services.library.imageData(for: suggestion.assetID) else {
                    shareState = .failed(String(localized: "This photo is no longer on your iPhone."))
                    return false
                }
                // The zone is shared with all participants. Anyone in my share will see the post.
                let recipients = friendships.filter { $0.outgoing != .none }.map(\.id)
                _ = try await services.shareService.share(suggestion, imageData: data, with: recipients)
            }
            try await decide(.share, for: suggestion)
            shareState = .idle
            shareSuccessCount += 1
            if !isDemo { await refreshSharing() }
            return true
        } catch ShareError.noRecipients {
            shareState = .failed(String(localized: "Add a friend first."))
        } catch {
            shareState = .failed(String(localized: "Couldn't share. Check your connection and try again."))
        }
        return false
    }

    func skip() async {
        guard let suggestion = pending else { return }
        try? await decide(.skip, for: suggestion)
    }

    private func decide(_ decision: ShareDecision, for suggestion: Suggestion) async throws {
        var decided = suggestion
        decided.decision = decision
        if isDemo {
            pending = nil
            decidedToday = decided
            return
        }
        var history = await services.history.load()
        history.record(decision, for: suggestion.id)
        try await services.history.save(history)
        pending = nil
        decidedToday = Self.decidedToday(in: history) ?? decided
    }

    func deleteAllData() async {
        try? await services.deleteAllLocalAndSharedData()
        appleUserID = nil
        userName = nil
        hasCompletedFirstScan = false
        pending = nil
        decidedToday = nil
        homeSheet = nil
        feed = []
        friends = []
        friendships = []
    }

    // MARK: Find moments now

    var isManualScanRunning: Bool {
        if case .running = manualScan { true } else { false }
    }

    /// Runs one analysis pass in the foreground with progress. The AI still picks: the user never chooses a photo.
    func findMomentsNow() {
        guard !isManualScanRunning else { return }
        guard photoAccess == .authorized else {
            manualScan = .finished(.needsFullAccess)
            return
        }
        let stop = StopSignal()
        manualScanStop = stop
        manualScan = .running(AnalysisProgress(completed: 0, total: 0, phase: .scanning))
        let services = services
        manualScanTask = Task { [weak self] in
            let result: ManualScanResult
            do {
                let outcome = try await services.runWithProgress(shouldContinue: { !stop.isSet }) { p in
                    Task { @MainActor in self?.applyManual(p) }
                }
                if outcome.suggestion != nil {
                    result = .foundMoment
                } else if !outcome.analysis.isComplete {
                    result = .stopped
                } else {
                    result = .nothingYet
                }
            } catch AppServices.PassError.busy {
                result = .busy
            } catch AppServices.PassError.needsFullAccess {
                result = .needsFullAccess
            } catch is CancellationError {
                result = .stopped
            } catch {
                result = .failed
            }
            await self?.finishManual(result)
        }
    }

    func cancelFindMoments() {
        manualScanStop?.set()
        manualScanTask?.cancel()
    }

    private func applyManual(_ progress: AnalysisProgress) {
        guard isManualScanRunning else { return }
        manualScan = .running(progress)
    }

    private func finishManual(_ result: ManualScanResult) async {
        manualScanTask = nil
        manualScanStop = nil
        pending = await services.history.load().pending
        analyzedPhotoCount = (try? await services.analysisCache.records().count) ?? analyzedPhotoCount
        manualScan = .finished(result)
    }

    // MARK: Debug launch arguments

    #if DEBUG
    /// Screenshot and test helpers. Debug builds only.
    /// `-resetOnboarding YES` starts onboarding again. `-skipOnboarding YES` opens the tabs.
    /// `-onboardingPage N` (1-based) opens that onboarding page. `-demoProgress YES` shows a fixed progress state.
    /// `-demoContent YES` and `-demoState <state>` load fixture content, see `DemoContent`.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if DemoContent.isEnabled { DemoContent.apply(to: self) }
        if defaults.bool(forKey: "resetOnboarding") {
            appleUserID = nil
            hasCompletedFirstScan = false
            if isDemo {
                photoAccess = .notDetermined
                notificationAccess = .notDetermined
            }
        }
        if defaults.bool(forKey: "skipOnboarding") {
            if appleUserID == nil { appleUserID = "debug-user" }
            hasCompletedFirstScan = true
        }
        if defaults.bool(forKey: "demoProgress") {
            if appleUserID == nil { appleUserID = "debug-user" }
            let demo = AnalysisProgress(completed: 37, total: 120, phase: .analyzing)
            firstScan = .scanning(demo)
            manualScan = .running(demo)
        }
    }

    static var debugOnboardingPage: Int? {
        let page = UserDefaults.standard.integer(forKey: "onboardingPage")
        return page > 0 ? page - 1 : nil
    }
    #endif
}

/// A stop request that a `shouldContinue` closure can read from any thread.
final class StopSignal: Sendable {
    private let value = Mutex(false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}
#endif
