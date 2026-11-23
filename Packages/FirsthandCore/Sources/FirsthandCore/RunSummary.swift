import Foundation

/// Why a run made no suggestion. The first matching reason wins, in this order.
public enum NoSuggestionReason: String, Sendable, Codable, Equatable {
    /// The run stopped before all photos were analyzed.
    case interrupted
    /// An undecided suggestion exists. There is never a second option.
    case pendingSuggestion
    /// Today's suggestion was already made (daily cap).
    case alreadyDecidedToday
    /// The last suggestion is too recent (cooldown).
    case cooldown
    /// No photos in the lookback window.
    case noPhotos
    /// Photos exist, but no analysis succeeded.
    case allFailed
    /// Photos were analyzed, but none can be suggested (screenshots, excluded, or already used moments).
    case nothingEligible
    /// The best photo scored below the threshold.
    case belowThreshold
}

/// What one run found, for user copy and the debug scoring log.
public struct RunSummary: Sendable, Codable, Equatable {
    /// Photos in the lookback window.
    public var photosFound: Int
    /// Photos with an analysis result.
    public var analyzed: Int
    /// Photos whose analysis failed. They are retried until they reach the attempt limit.
    public var failed: Int
    /// Screenshots and other assets that are never analyzed.
    public var excluded: Int
    /// Analyzed photos that can be suggested, in moments that were not suggested before.
    public var eligible: Int
    /// Score of the best eligible moment, or `nil` when there is none.
    public var bestScore: Double?
    public var threshold: Double
    public var lookbackDays: Int
    /// `nil` when the run made a suggestion.
    public var reason: NoSuggestionReason?
    /// When the cooldown ends, for `reason == .cooldown`.
    public var nextAllowed: Date?

    public init(
        photosFound: Int = 0,
        analyzed: Int = 0,
        failed: Int = 0,
        excluded: Int = 0,
        eligible: Int = 0,
        bestScore: Double? = nil,
        threshold: Double,
        lookbackDays: Int,
        reason: NoSuggestionReason? = nil,
        nextAllowed: Date? = nil
    ) {
        self.photosFound = photosFound
        self.analyzed = analyzed
        self.failed = failed
        self.excluded = excluded
        self.eligible = eligible
        self.bestScore = bestScore
        self.threshold = threshold
        self.lookbackDays = lookbackDays
        self.reason = reason
        self.nextAllowed = nextAllowed
    }

    /// The reason from the counts and the engine gate. `suggested` wins over everything.
    public static func reason(
        suggested: Bool,
        isComplete: Bool,
        gate: SuggestionGate?,
        photosFound: Int,
        analyzed: Int,
        failed: Int,
        bestScore: Double?,
        threshold: Double
    ) -> NoSuggestionReason? {
        if suggested { return nil }
        if !isComplete { return .interrupted }
        switch gate {
        case .pendingSuggestion: return .pendingSuggestion
        case .dailyCap: return .alreadyDecidedToday
        case .cooldown: return .cooldown
        case nil: break
        }
        if photosFound == 0 { return .noPhotos }
        if analyzed == 0 && failed > 0 { return .allFailed }
        guard bestScore != nil else { return .nothingEligible }
        return .belowThreshold
    }
}

/// One photo of the window as the scorer saw it. Debug scoring log only.
public struct ScoringLogEntry: Sendable, Codable, Equatable, Identifiable {
    public var assetID: String
    public var captureDate: Date
    /// `nil` when the photo was not analyzed (failed or excluded).
    public var signals: AnalysisSignals?
    /// Full score in its moment. `nil` when there are no signals.
    public var score: Double?
    public var isEligible: Bool
    public var passesThreshold: Bool
    public var isNewPlace: Bool
    /// The best photo of its moment, the one the engine compares.
    public var isMomentBest: Bool
    /// Its moment contains a photo that was suggested before.
    public var isAlreadyUsed: Bool
    public var isExcluded: Bool
    public var failure: AnalysisFailure?
    public var hasAdjustments: Bool

    public var id: String { assetID }

    public init(
        assetID: String,
        captureDate: Date,
        signals: AnalysisSignals? = nil,
        score: Double? = nil,
        isEligible: Bool = false,
        passesThreshold: Bool = false,
        isNewPlace: Bool = false,
        isMomentBest: Bool = false,
        isAlreadyUsed: Bool = false,
        isExcluded: Bool = false,
        failure: AnalysisFailure? = nil,
        hasAdjustments: Bool = false
    ) {
        self.assetID = assetID
        self.captureDate = captureDate
        self.signals = signals
        self.score = score
        self.isEligible = isEligible
        self.passesThreshold = passesThreshold
        self.isNewPlace = isNewPlace
        self.isMomentBest = isMomentBest
        self.isAlreadyUsed = isAlreadyUsed
        self.isExcluded = isExcluded
        self.failure = failure
        self.hasAdjustments = hasAdjustments
    }
}
