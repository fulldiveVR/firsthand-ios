#if os(iOS)
import CandidCore
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
    var feed: [Post] = []
    var shareState: ShareState = .idle

    private static let userKey = "appleUserID"

    init(services: AppServices) {
        self.services = services
        appleUserID = UserDefaults.standard.string(forKey: Self.userKey)
    }

    var isOnboarded: Bool { appleUserID != nil && photoAccess.canRead }

    func refresh() async {
        photoAccess = await services.library.authorizationStatus()
        pending = await services.history.load().pending
        friends = (try? await services.friends.friends()) ?? []
        feed = Post.chronological((try? await services.shareService.feed()) ?? [])
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
            let recipients = friends.filter { $0.status == .accepted }.map(\.id)
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
    }

    #if DEBUG
    func analyzeNow() async {
        _ = try? await services.runAnalysis()
        await refresh()
    }
    #endif
}
#endif
