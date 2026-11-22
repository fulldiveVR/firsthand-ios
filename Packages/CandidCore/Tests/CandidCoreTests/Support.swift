import Foundation
@testable import CandidCore

let day0 = Date(timeIntervalSince1970: 1_800_000_000)

var utcCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

func signals(
    aesthetic: Double = 0.5,
    utility: Bool = false,
    faces: Int = 0,
    labels: Set<String> = [],
    screenshot: Bool = false,
    exif: Bool = true
) -> AnalysisSignals {
    AnalysisSignals(
        aestheticScore: aesthetic,
        isUtility: utility,
        faceCount: faces,
        sceneLabels: labels,
        isScreenshot: screenshot,
        hasCameraEXIF: exif
    )
}

func candidate(
    _ id: String,
    burst: String? = nil,
    place: String? = nil,
    _ s: AnalysisSignals = signals()
) -> PhotoCandidate {
    PhotoCandidate(assetID: id, captureDate: day0, locationBucket: place, burstIdentifier: burst, signals: s)
}

struct FakeLibrary: PhotoLibrary {
    var assets: [PhotoAsset]

    func authorizationStatus() async -> PhotoAuthorization { .authorized }
    func requestAuthorization() async -> PhotoAuthorization { .authorized }
    func recentAssets(since: Date, limit: Int) async throws -> [PhotoAsset] {
        Array(assets.filter { $0.captureDate >= since }.prefix(limit))
    }
    func imageData(for assetID: String) async throws -> Data? { Data() }
}

/// Records which assets it analyzed.
actor RecordingAnalyzer: ImageAnalyzer {
    private(set) var analyzed: [String] = []
    var failing: Set<String> = []

    init(failing: Set<String> = []) {
        self.failing = failing
    }

    func analyze(_ asset: PhotoAsset) async throws -> AnalysisSignals {
        analyzed.append(asset.id)
        struct Broken: Error {}
        if failing.contains(asset.id) { throw Broken() }
        return signals(faces: 1, labels: ["outdoor"])
    }
}

/// Thread-safe counter for `shouldContinue` closures.
final class Budget: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int

    init(_ n: Int) { remaining = n }

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
    }
}

actor RecordingNotifier: Notifier {
    private(set) var notified: [Suggestion] = []
    func requestAuthorization() async -> Bool { true }
    func notifySuggestionReady(_ suggestion: Suggestion) async { notified.append(suggestion) }
}
