import Foundation
import Testing
@testable import FirsthandCore

@Suite struct MomentReasonTests {
    func reasons(_ s: AnalysisSignals, newPlace: Bool = false, age: TimeInterval = 3600) -> [MomentReason] {
        MomentReason.reasons(signals: s, isNewPlace: newPlace, captureDate: day0.addingTimeInterval(-age), now: day0)
    }

    @Test func mapsEverySignalInDisplayOrder() {
        let r = reasons(signals(faces: 3, labels: ["outdoor", "beach"]), newPlace: true)
        #expect(r == [.newPlace, .withFriends, .scene("beach"), .today, .provenance(.likelyCamera)])
    }

    @Test func oneFaceIsWithSomeone() {
        #expect(reasons(signals(faces: 1)).contains(.withSomeone))
        #expect(!reasons(signals(faces: 0)).contains(.withSomeone))
        #expect(!reasons(signals(faces: 0)).contains(.withFriends))
    }

    @Test func onlyRewardedScenesCount() {
        #expect(reasons(signals(labels: ["document", "food"])).allSatisfy { if case .scene = $0 { false } else { true } })
        #expect(reasons(signals(labels: ["sky", "outdoor"])).contains(.scene("sky")))
    }

    @Test func todayOnlyWithin24Hours() {
        #expect(reasons(signals(), age: 23 * 3600).contains(.today))
        #expect(!reasons(signals(), age: 25 * 3600).contains(.today))
    }

    @Test func provenanceIsLikelyOriginalOrUnknownNeverVerified() {
        #expect(reasons(signals(exif: true)).last == .provenance(.likelyCamera))
        #expect(reasons(signals(exif: false)).last == .provenance(.unknown))
        #expect(MomentReason.provenance(.likelyCamera).title == "Likely original")
        #expect(MomentReason.provenance(.hasReferenceImageData).title == "Likely original")
        #expect(MomentReason.provenance(.unknown).title == "Unknown")
        let all = ProvenanceStatus.allCases.map { MomentReason.provenance($0).title.lowercased() }
        #expect(all.allSatisfy { !$0.contains("verified") })
    }

    @Test func chipsKeepAtMostThreeWithProvenanceLast() {
        let all: [MomentReason] = [.newPlace, .withFriends, .scene("beach"), .today, .provenance(.likelyCamera)]
        #expect(MomentReason.chips(all) == [.newPlace, .withFriends, .provenance(.likelyCamera)])
        #expect(MomentReason.chips([.today]) == [.today])
        #expect(MomentReason.chips([.provenance(.unknown)]) == [.provenance(.unknown)])
    }

    @Test func engineFillsReasonsAndCaptureDate() {
        let engine = SuggestionEngine(calendar: utcCalendar)
        let scored = MomentScorer().score([candidate("a", at: day0.addingTimeInterval(-600), signals(aesthetic: 0.9, faces: 2, labels: ["beach"]))], context: ctx0)
        let s = engine.pick(from: scored, history: SuggestionHistory(), now: day0, newPlaceAssetIDs: ["a"])
        #expect(s?.reasons == [.newPlace, .withFriends, .scene("beach"), .today, .provenance(.likelyCamera)])
        #expect(s?.captureDate == day0.addingTimeInterval(-600))
    }

    @Test func oldHistoryDecodesWithEmptyReasons() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","assetID":"x","score":1,"provenance":"unknown","sceneLabels":[],"createdAt":0}"#
        let s = try JSONDecoder().decode(Suggestion.self, from: Data(json.utf8))
        #expect(s.reasons.isEmpty)
        #expect(s.captureDate == nil)
        #expect(s.displayReasons == [.provenance(.unknown)])
    }

    @Test func reasonsRoundTrip() throws {
        var s = Suggestion(assetID: "x", score: 1, provenance: .likelyCamera, createdAt: day0)
        s.reasons = [.newPlace, .scene("lake"), .provenance(.likelyCamera)]
        s.captureDate = day0
        let back = try JSONDecoder().decode(Suggestion.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}
