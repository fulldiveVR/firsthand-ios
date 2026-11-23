#if os(iOS)
import FirsthandCore
import SwiftUI

extension AnalysisProgress {
    var phaseTitle: String {
        switch phase {
        case .scanning: String(localized: "Looking for recent photos")
        case .analyzing: String(localized: "Analyzing photos")
        case .choosing: String(localized: "Choosing the best moment")
        }
    }

    /// Short status line, also used by the system progress UI of the first scan.
    var subtitle: String {
        guard phase == .analyzing, total > 0 else { return phaseTitle }
        return String(localized: "\(completed) of \(total) photos")
    }
}

/// Phase, photo count, percentage and a bar. Shared by the first scan and "Find moments now".
struct AnalysisProgressView: View {
    let progress: AnalysisProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.phaseTitle).font(.subheadline.weight(.semibold))
                Spacer()
                if progress.phase != .scanning {
                    Text("\(progress.percent)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if progress.phase == .scanning {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: progress.fractionCompleted)
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch progress.phase {
        case .scanning:
            String(localized: "Checking which photos are new.")
        case .analyzing where progress.total == 0:
            String(localized: "No new photos to analyze.")
        case .analyzing:
            String(localized: "\(progress.completed) of \(progress.total) photos analyzed")
        case .choosing:
            String(localized: "Grouping moments and picking one.")
        }
    }
}

/// "Find moments now": runs the analysis in the foreground. The AI picks, the user never chooses a photo.
struct FindMomentsPanel: View {
    @Environment(AppModel.self) private var model
    /// `true` shows the button with a prominent style.
    var prominent = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.manualScan {
            case .running(let progress):
                AnalysisProgressView(progress: progress)
                Button("Cancel", role: .cancel) { model.cancelFindMoments() }
                    .buttonStyle(.bordered)
            case .idle:
                startButton
            case .finished(let result):
                Label(result.message, systemImage: result.symbol)
                    .font(.subheadline)
                    .foregroundStyle(result == .foundMoment ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                if result == .needsFullAccess {
                    Button("Open Settings") { SystemSettings.open() }
                        .buttonStyle(.bordered)
                } else if result != .foundMoment {
                    startButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.default, value: model.manualScan)
    }

    @ViewBuilder
    private var startButton: some View {
        let button = Button {
            model.findMomentsNow()
        } label: {
            Label("Find moments now", systemImage: "sparkle.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

extension AppModel.ManualScanResult {
    var message: String {
        switch self {
        case .foundMoment: String(localized: "Found a moment. It is on Today.")
        case .nothingYet: String(localized: "Nothing stood out yet.")
        case .stopped: String(localized: "Stopped. Photos analyzed so far are saved.")
        case .busy: String(localized: "Analysis is already running. Try again in a minute.")
        case .needsFullAccess: String(localized: "Full photo access is needed to find new moments.")
        case .failed: String(localized: "Something went wrong. Try again later.")
        }
    }

    var symbol: String {
        switch self {
        case .foundMoment: "sparkles"
        case .nothingYet: "leaf"
        case .stopped: "pause.circle"
        case .busy: "hourglass"
        case .needsFullAccess: "photo.badge.exclamationmark"
        case .failed: "exclamationmark.triangle"
        }
    }
}

enum SystemSettings {
    @MainActor
    static func open() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
#endif
