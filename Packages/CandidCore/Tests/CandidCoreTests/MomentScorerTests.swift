import Foundation
import Testing
@testable import CandidCore

@Suite struct ProvenanceTests {
    @Test func screenshotsAreExcluded() {
        #expect(ProvenanceStatus.classify(isScreenshot: true, hasCameraEXIF: true) == .excluded)
    }

    @Test func cameraEXIFIsOnlyLikelyCamera() {
        #expect(ProvenanceStatus.classify(isScreenshot: false, hasCameraEXIF: true) == .likelyCamera)
    }

    @Test func noEXIFIsUnknown() {
        #expect(ProvenanceStatus.classify(isScreenshot: false, hasCameraEXIF: false) == .unknown)
    }

    @Test func referenceImageDataWinsOverEXIF() {
        let p = ProvenanceStatus.classify(isScreenshot: false, hasCameraEXIF: true, hasReferenceImageData: true)
        #expect(p == .hasReferenceImageData)
    }

    @Test func screenshotWinsOverReferenceImageData() {
        #expect(ProvenanceStatus.classify(isScreenshot: true, hasCameraEXIF: false, hasReferenceImageData: true) == .excluded)
    }
}

@Suite struct MomentScorerTests {
    let scorer = MomentScorer()

    @Test func isDeterministic() {
        let batch = [candidate("a", signals(faces: 2)), candidate("b", signals(labels: ["beach"])), candidate("c")]
        #expect(scorer.score(batch, context: ctx0) == scorer.score(batch, context: ctx0))
    }

    @Test func peopleBeatEmptyScenes() {
        let ranked = scorer.score([candidate("empty"), candidate("people", signals(faces: 1))], context: ctx0)
        #expect(ranked.first?.candidate.assetID == "people")
    }

    @Test func groupsBeatSingleFaces() {
        let ranked = scorer.score([candidate("one", signals(faces: 1)), candidate("group", signals(faces: 3))], context: ctx0)
        #expect(ranked.first?.candidate.assetID == "group")
    }

    @Test func outdoorAndActivityLabelsAreRewarded() {
        let ranked = scorer.score([candidate("desk", signals(labels: ["desk"])), candidate("hike", signals(labels: ["hiking"]))], context: ctx0)
        #expect(ranked.first?.candidate.assetID == "hike")
    }

    @Test func utilityIsPenalized() {
        let receipt = scorer.baseScore(candidate("r", signals(aesthetic: 1, utility: true)))
        // A plain photo of average quality beats a perfect receipt.
        let plain = scorer.baseScore(candidate("p", signals(aesthetic: 0.5)))
        #expect(receipt < plain)
    }

    @Test func screenshotsAreIneligible() {
        let ranked = scorer.score([candidate("s", signals(faces: 5, screenshot: true))], context: ctx0)
        #expect(ranked.first?.isEligible == false)
    }

    @Test func cameraOriginalBeatsUnknownProvenance() {
        let ranked = scorer.score([candidate("unknown", signals(exif: false)), candidate("camera", signals(exif: true))], context: ctx0)
        #expect(ranked.first?.candidate.assetID == "camera")
    }

    @Test func recentSceneAndPlaceReduceNovelty() {
        let recent = Suggestion(
            assetID: "old", score: 1, provenance: .likelyCamera,
            sceneLabels: ["beach", "ocean"], locationBucket: "cell-1", createdAt: day0
        )
        let ranked = scorer.score(
            [
                candidate("same", place: "cell-1", signals(labels: ["beach", "ocean"])),
                candidate("new", place: "cell-2", signals(labels: ["mountain", "snow"])),
            ],
            context: ScoringContext(now: day0, recentSuggestions: [recent])
        )
        #expect(ranked.map(\.candidate.assetID) == ["new", "same"])
    }

    @Test func tiesBreakByAssetID() {
        let ranked = scorer.score([candidate("b"), candidate("a")], context: ctx0)
        #expect(ranked.map(\.candidate.assetID) == ["a", "b"])
    }
}
