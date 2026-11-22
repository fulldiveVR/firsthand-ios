import Foundation
import Testing
@testable import CandidCore

private let minute: TimeInterval = 60
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400

@Suite struct MomentGroupingTests {
    let grouping = MomentGrouping()

    @Test func gapLongerThan45MinutesStartsANewMoment() {
        let moments = grouping.group([
            candidate("a", at: day0),
            candidate("b", at: day0.addingTimeInterval(30 * minute)),
            // 45 min after "b" is still the same moment, 46 min after "c" is not.
            candidate("c", at: day0.addingTimeInterval(75 * minute)),
            candidate("d", at: day0.addingTimeInterval(121 * minute)),
        ])
        #expect(moments.map { $0.candidates.map(\.assetID) } == [["a", "b", "c"], ["d"]])
        #expect(moments.map(\.id) == ["a", "d"])
        #expect(moments[0].end == day0.addingTimeInterval(75 * minute))
    }

    @Test func placeChangeStartsANewMoment() {
        let input = [
            candidate("a", at: day0, place: "x"),
            candidate("b", at: day0.addingTimeInterval(5 * minute)),
            candidate("c", at: day0.addingTimeInterval(10 * minute), place: "y"),
        ]
        #expect(grouping.group(input).map { $0.candidates.map(\.assetID) } == [["a", "b"], ["c"]])

        var config = MomentGrouping.Config()
        config.splitOnPlaceChange = false
        #expect(MomentGrouping(config: config).group(input).count == 1)
    }

    @Test func groupingIgnoresInputOrder() {
        let input = (0..<6).map { candidate("p\($0)", at: day0.addingTimeInterval(Double($0) * 20 * minute)) }
        #expect(grouping.group(input) == grouping.group(input.reversed()))
    }

    @Test func burstCollapsesToTheBestPhoto() {
        let scorer = MomentScorer()
        let kept = grouping.collapseDuplicates([
            candidate("b1", at: day0, burst: "x", signals(aesthetic: 0.6)),
            candidate("b2", at: day0.addingTimeInterval(20), burst: "x", signals(aesthetic: 0.9)),
            candidate("other", at: day0.addingTimeInterval(60)),
        ]) { scorer.baseScore($0) > scorer.baseScore($1) }
        #expect(kept.map(\.assetID) == ["b2", "other"])
    }

    @Test func photosWithinAFewSecondsCollapse() {
        let kept = grouping.collapseDuplicates([
            candidate("a", at: day0, signals(aesthetic: 0.5)),
            candidate("b", at: day0.addingTimeInterval(2), signals(aesthetic: 0.8)),
            candidate("c", at: day0.addingTimeInterval(4), signals(aesthetic: 0.6)),
            candidate("far", at: day0.addingTimeInterval(30)),
        ]) { $0.signals.aestheticScore > $1.signals.aestheticScore }
        // a, b, c chain within 3 s of each other.
        #expect(kept.map(\.assetID) == ["b", "far"])
    }
}

@Suite struct MomentScoringSignalTests {
    let scorer = MomentScorer()
    let w = MomentScorer.Weights()

    @Test func peopleBonusIsCapped() {
        let three = scorer.baseScore(candidate("3", signals(faces: 3)))
        let twelve = scorer.baseScore(candidate("12", signals(faces: 12)))
        let one = scorer.baseScore(candidate("1", signals(faces: 1)))
        #expect(three == twelve)
        #expect(abs((three - one) - Double(w.maxExtraFaces) * w.perExtraFace) < 1e-9)
    }

    @Test func groupSelfieDoesNotBeatAGreatOutdoorPhoto() {
        let selfie = scorer.baseScore(candidate("selfie", signals(aesthetic: 0.5, faces: 10)))
        let hike = scorer.baseScore(candidate("hike", signals(aesthetic: 0.8, faces: 1, labels: ["hiking"])))
        #expect(hike > selfie)
    }

    @Test func recentPhotosScoreHigher() {
        let ctx = ScoringContext(now: day0.addingTimeInterval(3 * day))
        let fresh = scorer.score(candidate("fresh", at: day0.addingTimeInterval(3 * day - hour)), momentStart: day0, context: ctx)
        let old = scorer.score(candidate("old", at: day0), momentStart: day0, context: ctx)
        #expect(fresh.score > old.score)
        #expect(scorer.recencyFactor(day0, now: day0.addingTimeInterval(48 * hour)) == 0)
        #expect(scorer.recencyFactor(day0, now: day0) == 1)
    }

    @Test func editedPhotosArePenalized() {
        let original = scorer.baseScore(candidate("o"))
        let edited = scorer.baseScore(candidate("e", adjusted: true))
        #expect(abs((original - edited) - w.adjustedPenalty) < 1e-9)
    }

    @Test func lowAestheticsArePenalized() {
        let low = scorer.baseScore(candidate("low", signals(aesthetic: 0.3)))
        let ok = scorer.baseScore(candidate("ok", signals(aesthetic: 0.4)))
        #expect(ok - low > w.lowAestheticPenalty)
    }

    @Test func newPlaceGetsABonus() {
        let start = day0.addingTimeInterval(40 * day)
        let history = PlaceHistory(visits: [
            ("home", day0.addingTimeInterval(20 * day)),
            ("work", day0.addingTimeInterval(39 * day)),
        ])
        let ctx = ScoringContext(now: start, placeHistory: history)
        let beach = scorer.score(candidate("beach", at: start, place: "beach"), momentStart: start, context: ctx)
        let work = scorer.score(candidate("work", at: start, place: "work"), momentStart: start, context: ctx)
        #expect(abs((beach.score - work.score) - w.newPlace) < 1e-9)
        #expect(scorer.isNewPlace(beach.candidate, momentStart: start, context: ctx))
    }

    @Test func placeSeenLongAgoCountsAsNew() {
        let start = day0.addingTimeInterval(40 * day)
        let history = PlaceHistory(visits: [("beach", day0), ("home", start.addingTimeInterval(-day))])
        #expect(history.isNew("beach", before: start, window: w.newPlaceWindow))
    }

    @Test func noOtherVisitsMeansNoNewPlaceEvidence() {
        let history = PlaceHistory(visits: [("beach", day0)])
        #expect(!history.isNew("beach", before: day0, window: w.newPlaceWindow))
        // The beach visit is evidence that the user was elsewhere, so the park is new.
        #expect(history.isNew("park", before: day0.addingTimeInterval(day), window: w.newPlaceWindow))
        #expect(!PlaceHistory().isNew("park", before: day0, window: w.newPlaceWindow))
    }

    @Test func photosOfTheSameMomentDoNotHideTheNewPlace() {
        // History contains the moment's own photos. Only visits before the moment start count.
        let start = day0.addingTimeInterval(10 * day)
        let history = PlaceHistory(visits: [
            ("home", start.addingTimeInterval(-day)),
            ("beach", start), ("beach", start.addingTimeInterval(10 * minute)),
        ])
        #expect(history.isNew("beach", before: start, window: w.newPlaceWindow))
    }
}

@Suite struct MomentRankerTests {
    let ranker = MomentRanker()

    @Test func picksTheBestPhotoPerMomentThenTheBestMoment() {
        let morning = day0
        let evening = day0.addingTimeInterval(10 * hour)
        let ranked = ranker.rank(
            [
                candidate("m1", at: morning, signals(aesthetic: 0.5, faces: 1)),
                candidate("m2", at: morning.addingTimeInterval(10 * minute), signals(aesthetic: 0.9, faces: 1)),
                candidate("e1", at: evening, signals(aesthetic: 0.9, faces: 2, labels: ["party"])),
                candidate("e2", at: evening.addingTimeInterval(5 * minute), signals(aesthetic: 0.4)),
            ],
            context: ScoringContext(now: evening)
        )
        #expect(ranked.map(\.best.candidate.assetID) == ["e1", "m2"])
        #expect(ranked.map(\.moment.id) == ["e1", "m1"])
    }

    @Test func burstDuplicatesNeverReachTheEngine() {
        let ranked = ranker.rank(
            (0..<5).map { candidate("b\($0)", at: day0.addingTimeInterval(Double($0)), burst: "x", signals(faces: 1)) },
            context: ctx0
        )
        #expect(ranked.count == 1)
        #expect(ranked[0].moment.candidates.count == 1)
    }

    @Test func screenshotIsNeverTheBestOfAMoment() {
        let ranked = ranker.rank(
            [
                candidate("shot", at: day0, signals(aesthetic: 1, faces: 5, screenshot: true)),
                candidate("photo", at: day0.addingTimeInterval(10 * minute), signals(aesthetic: 0.2)),
            ],
            context: ctx0
        )
        #expect(ranked.first?.best.candidate.assetID == "photo")
    }

    @Test func excludedAssetBlocksItsWholeMoment() {
        let input = [
            candidate("a", at: day0, signals(aesthetic: 0.9, faces: 1)),
            candidate("a2", at: day0.addingTimeInterval(1), signals(aesthetic: 0.2)),
            candidate("b", at: day0.addingTimeInterval(5 * minute), signals(aesthetic: 0.8, faces: 1)),
            candidate("later", at: day0.addingTimeInterval(5 * hour), signals(aesthetic: 0.6, faces: 1)),
        ]
        #expect(ranker.rank(input, context: ctx0, excludedAssetIDs: ["a"]).map(\.best.candidate.assetID) == ["later"])
        // "a2" was collapsed into "a", but it still blocks the moment.
        #expect(ranker.rank(input, context: ctx0, excludedAssetIDs: ["a2"]).map(\.best.candidate.assetID) == ["later"])
    }

    @Test func rankingIsDeterministic() {
        let input = (0..<20).map {
            candidate("p\($0)", at: day0.addingTimeInterval(Double($0) * 17 * minute), signals(aesthetic: Double($0 % 5) / 5, faces: $0 % 3))
        }
        #expect(ranker.rank(input, context: ctx0) == ranker.rank(input.reversed(), context: ctx0))
    }
}

@Suite struct QualityThresholdTests {
    let ranker = MomentRanker()
    let engine = SuggestionEngine(calendar: utcCalendar)

    @Test func plainPhotosProduceNoSuggestion() {
        let ranked = ranker.rank(
            [
                candidate("desk", at: day0, signals(aesthetic: 0.6, labels: ["desk"])),
                candidate("wall", at: day0.addingTimeInterval(2 * hour), signals(aesthetic: 0.7)),
            ],
            context: ctx0
        )
        #expect(!ranked.isEmpty)
        #expect(ranked.allSatisfy { $0.score < engine.policy.minimumScore })
        #expect(engine.pick(from: ranked, history: SuggestionHistory(), now: day0) == nil)
    }

    @Test func aMeaningfulPhotoPasses() {
        let ranked = ranker.rank([candidate("friends", signals(aesthetic: 0.6, faces: 2))], context: ctx0)
        #expect(engine.pick(from: ranked, history: SuggestionHistory(), now: day0)?.assetID == "friends")
    }

    @Test func thresholdIsAConfigValue() {
        let strict = SuggestionEngine(policy: SuggestionPolicy(minimumScore: 2), calendar: utcCalendar)
        let ranked = ranker.rank([candidate("friends", signals(aesthetic: 1, faces: 2, labels: ["party"]))], context: ctx0)
        #expect(strict.pick(from: ranked, history: SuggestionHistory(), now: day0) == nil)
    }

    @Test func atMostOneSuggestionPerDayByDefault() {
        #expect(SuggestionPolicy().dailyCap == 1)
        let ranked = ranker.rank(
            [
                candidate("a", at: day0, signals(aesthetic: 0.9, faces: 2)),
                candidate("b", at: day0.addingTimeInterval(5 * hour), signals(aesthetic: 0.9, faces: 2)),
            ],
            context: ctx0
        )
        let noCooldown = SuggestionEngine(policy: SuggestionPolicy(cooldown: 0), calendar: utcCalendar)
        let start = utcCalendar.startOfDay(for: day0)
        var first = noCooldown.pick(from: ranked, history: SuggestionHistory(), now: start)!
        first.decision = .skip
        #expect(noCooldown.pick(from: ranked, history: SuggestionHistory(suggestions: [first]), now: start.addingTimeInterval(hour)) == nil)
    }
}

@Suite struct MomentPipelineTests {
    func pipeline(_ assets: [PhotoAsset], analyzer: ImageAnalyzer = RecordingAnalyzer(), captioner: (any MomentCaptioner)? = nil) -> SuggestionPipeline {
        SuggestionPipeline(
            queue: AnalysisQueue(library: FakeLibrary(assets: assets), analyzer: analyzer, cache: InMemoryAnalysisCache()),
            engine: SuggestionEngine(calendar: utcCalendar),
            notifier: RecordingNotifier(),
            captioner: captioner,
            clock: FixedClock(day0.addingTimeInterval(hour))
        )
    }

    @Test func captionIsAddedWhenAvailable() async throws {
        let assets = [PhotoAsset(id: "p1", captureDate: day0)]
        let s = try await pipeline(assets, captioner: FixedCaptioner(text: "Out in the sun")).run(history: SuggestionHistory())
        #expect(s?.caption == "Out in the sun")
        let none = try await pipeline(assets, captioner: FixedCaptioner(text: nil)).run(history: SuggestionHistory())
        #expect(none != nil && none?.caption == nil)
    }

    @Test func skippedMomentIsNotSuggestedAgain() async throws {
        let assets = [
            PhotoAsset(id: "p1", captureDate: day0),
            PhotoAsset(id: "p2", captureDate: day0.addingTimeInterval(10 * minute)),
        ]
        let p = pipeline(assets)
        var first = try #require(try await p.run(history: SuggestionHistory()))
        first.decision = .skip
        first.createdAt = day0.addingTimeInterval(-2 * day)
        #expect(try await p.run(history: SuggestionHistory(suggestions: [first])) == nil)
    }

    @Test func newPlaceFromLibraryMetadataWinsOverHome() async throws {
        var assets = [
            PhotoAsset(id: "home", captureDate: day0.addingTimeInterval(-3 * hour), locationBucket: "home"),
            PhotoAsset(id: "trip", captureDate: day0, locationBucket: "beach"),
        ]
        // Older metadata, outside the analysis lookback: many visits at home.
        assets += (4...13).map { PhotoAsset(id: "old\($0)", captureDate: day0.addingTimeInterval(-Double($0) * day), locationBucket: "home") }
        let analyzer = RecordingAnalyzer()
        let s = try await pipeline(assets, analyzer: analyzer).run(history: SuggestionHistory())
        #expect(s?.assetID == "trip")
        // Old photos are metadata only and never analyzed.
        #expect(await !analyzer.analyzed.contains { $0.hasPrefix("old") })
    }
}
