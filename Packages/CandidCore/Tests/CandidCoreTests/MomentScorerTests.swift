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
        #expect(scorer.score(batch) == scorer.score(batch))
    }

    @Test func peopleBeatEmptyScenes() {
        let ranked = scorer.score([candidate("empty"), candidate("people", signals(faces: 1))])
        #expect(ranked.first?.candidate.assetID == "people")
    }

    @Test func groupsBeatSingleFaces() {
        let ranked = scorer.score([candidate("one", signals(faces: 1)), candidate("group", signals(faces: 3))])
        #expect(ranked.first?.candidate.assetID == "group")
    }

    @Test func outdoorAndActivityLabelsAreRewarded() {
        let ranked = scorer.score([candidate("desk", signals(labels: ["desk"])), candidate("hike", signals(labels: ["hiking"]))])
        #expect(ranked.first?.candidate.assetID == "hike")
    }

    @Test func utilityIsPenalized() {
        let receipt = scorer.baseScore(candidate("r", signals(aesthetic: 1, utility: true)))
        let plain = scorer.baseScore(candidate("p", signals(aesthetic: 0)))
        #expect(receipt < plain)
    }

    @Test func screenshotsAreIneligible() {
        let ranked = scorer.score([candidate("s", signals(faces: 5, screenshot: true))])
        #expect(ranked.first?.isEligible == false)
    }

    @Test func cameraOriginalBeatsUnknownProvenance() {
        let ranked = scorer.score([candidate("unknown", signals(exif: false)), candidate("camera", signals(exif: true))])
        #expect(ranked.first?.candidate.assetID == "camera")
    }

    @Test func onlyBestOfBurstAvoidsDuplicatePenalty() {
        let ranked = scorer.score([
            candidate("b1", burst: "x", signals(aesthetic: 0.9, faces: 1)),
            candidate("b2", burst: "x", signals(aesthetic: 0.8, faces: 1)),
        ])
        let b1 = ranked.first { $0.candidate.assetID == "b1" }!
        let b2 = ranked.first { $0.candidate.assetID == "b2" }!
        let w = MomentScorer.Weights()
        #expect(b1.score == scorer.baseScore(b1.candidate))
        #expect(abs(b2.score - (scorer.baseScore(b2.candidate) - w.duplicatePenalty)) < 1e-9)
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
            recentSuggestions: [recent]
        )
        #expect(ranked.map(\.candidate.assetID) == ["new", "same"])
    }

    @Test func tiesBreakByAssetID() {
        let ranked = scorer.score([candidate("b"), candidate("a")])
        #expect(ranked.map(\.candidate.assetID) == ["a", "b"])
    }
}
