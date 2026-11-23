#if os(iOS) && DEBUG
import FirsthandCore
import Foundation
import SwiftUI

/// Writes the last run to `debug-last-run.json` in the app container, for on-device checks. Debug builds only.
/// It holds asset ids, scores and labels. No pixels.
enum DebugRunLog {
    struct Snapshot: Codable {
        var date: Date
        var analyzedThisRun: Int
        var failedThisRun: Int
        var suggestedAssetID: String?
        var summary: RunSummary
        var log: [ScoringLogEntry]
    }

    static var url: URL { AppInfo.dataDirectory.appending(path: "debug-last-run.json") }

    static func write(_ outcome: PipelineOutcome) {
        let snapshot = Snapshot(
            date: Date(),
            analyzedThisRun: outcome.analysis.analyzedThisRun,
            failedThisRun: outcome.analysis.failedThisRun,
            suggestedAssetID: outcome.suggestion?.assetID,
            summary: outcome.summary,
            log: outcome.log
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}

/// Every photo of the analysis window with its score and signals, for tuning the threshold. Debug builds only.
struct ScoringLogView: View {
    @Environment(AppModel.self) private var model
    @State private var outcome: PipelineOutcome?
    @State private var error: String?
    @State private var sortByScore = false

    var body: some View {
        List {
            if let outcome {
                Section("Summary") { SummaryGrid(summary: outcome.summary) }
                Section {
                    ForEach(entries(outcome)) { entry in
                        ScoringLogRow(entry: entry, threshold: outcome.summary.threshold)
                    }
                } header: {
                    Picker("Sort", selection: $sortByScore) {
                        Text("Newest").tag(false)
                        Text("Score").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                }
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .listStyle(.plain)
        .navigationTitle("Scoring Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reload", systemImage: "arrow.clockwise") { Task { await load() } }
            }
        }
        .task { await load() }
        .onChange(of: model.isManualScanRunning) { _, running in
            if !running { Task { await load() } }
        }
        .refreshable { await load() }
    }

    private func entries(_ outcome: PipelineOutcome) -> [ScoringLogEntry] {
        guard sortByScore else { return outcome.log }
        return outcome.log.sorted { ($0.score ?? -.infinity) > ($1.score ?? -.infinity) }
    }

    private func load() async {
        do {
            let history = await model.services.history.load()
            outcome = try await model.services.makePipeline().report(history: history)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}

private struct SummaryGrid: View {
    let summary: RunSummary

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                stat("found", summary.photosFound)
                stat("analyzed", summary.analyzed)
                stat("failed", summary.failed)
            }
            GridRow {
                stat("excluded", summary.excluded)
                stat("eligible", summary.eligible)
                stat("days", summary.lookbackDays)
            }
            GridRow {
                Text("best \(summary.bestScore.map { $0.formatted(.number.precision(.fractionLength(3))) } ?? "–")")
                Text("min \(summary.threshold.formatted(.number.precision(.fractionLength(2))))")
                Text(summary.reason?.rawValue ?? "suggested")
                    .foregroundStyle(summary.reason == nil ? .green : .orange)
            }
        }
        .font(.caption.monospacedDigit())
    }

    private func stat(_ name: String, _ value: Int) -> some View {
        Text("\(name) \(value)")
    }
}

private struct ScoringLogRow: View {
    let entry: ScoringLogEntry
    let threshold: Double

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MomentPhoto(assetID: entry.assetID, side: 120)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.captureDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if entry.isMomentBest { tag("best", .blue) }
                    if entry.isAlreadyUsed { tag("used", .gray) }
                    if entry.isCollapsedDuplicate { tag("dup", .gray) }
                    scoreText
                }
                .font(.caption.monospacedDigit())
                if let s = entry.signals {
                    Text(signalLine(s))
                        .font(.caption2.monospacedDigit())
                    if !s.sceneLabels.isEmpty {
                        Text(s.sceneLabels.sorted().joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if let failure = entry.failure {
                    Text("failed ×\(failure.attempts)\(failure.attempts >= AnalysisRecord.maxAttempts ? " (gave up)" : ""): \(failure.reason)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if entry.isExcluded {
                    Text("excluded (screenshot)").font(.caption2).foregroundStyle(.secondary)
                } else if entry.signals == nil {
                    Text("not analyzed yet").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var scoreText: some View {
        if let score = entry.score {
            Text("\(score.formatted(.number.precision(.fractionLength(3)))) \(entry.passesThreshold ? "✓" : "✗")")
                .fontWeight(.semibold)
                .foregroundStyle(entry.passesThreshold ? .green : (entry.isEligible ? .orange : .red))
        } else {
            Text("–").foregroundStyle(.secondary)
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 4)
            .background(color.opacity(0.2), in: Capsule())
    }

    private func signalLine(_ s: AnalysisSignals) -> String {
        var parts = ["aes \(s.aestheticScore.formatted(.number.precision(.fractionLength(2))))"]
        parts.append("faces \(s.faceCount)")
        if s.isUtility { parts.append("UTILITY") }
        parts.append(s.provenance.rawValue)
        if s.hasCameraEXIF { parts.append("exif") }
        if entry.isNewPlace { parts.append("new place") }
        if entry.hasAdjustments { parts.append("edited") }
        if !entry.isEligible { parts.append("INELIGIBLE") }
        return parts.joined(separator: " · ")
    }
}
#endif
