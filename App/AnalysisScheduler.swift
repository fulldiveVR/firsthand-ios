#if os(iOS)
import BackgroundTasks
import FirsthandCore
import Foundation
import Synchronization

/// Two kinds of background work:
/// - Ongoing: `BGProcessingTask` while the phone charges. No network is needed.
/// - First scan: `BGContinuedProcessingTask` (iOS 26), started by the user in onboarding.
///   The system shows its progress and lets it finish when the user leaves the app.
enum AnalysisScheduler {
    /// Must run before the app finishes launching.
    static func register(services: AppServices) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppInfo.analysisTaskID, using: nil) { task in
            handle(task, services: services)
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: AppInfo.analysisTaskID)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Fails in the simulator and when Background App Refresh is off. The next launch retries.
        }
    }

    private static func handle(_ task: BGTask, services: AppServices) {
        schedule()
        let stop = StopFlag()
        let work = Task {
            let suggestion = try? await services.runAnalysis(shouldContinue: { !stop.isSet })
            return suggestion
        }
        // BGTask is not Sendable. The system allows these calls from any thread.
        nonisolated(unsafe) let task = task
        task.expirationHandler = {
            stop.set()
            work.cancel()
        }
        Task {
            _ = await work.value
            // The analysis cache keeps finished photos, so an early stop is still a success.
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: First scan

    /// Progress updates for the onboarding UI. Called from any thread.
    typealias FirstScanUpdate = @Sendable (FirstScanEvent) -> Void

    enum FirstScanEvent: Sendable {
        case progress(AnalysisProgress)
        case finished(Suggestion?, complete: Bool)
    }

    private static let firstScanRegistered = Mutex(false)
    /// The latest UI callback. The task handler is registered once and reads it at run time.
    private static let firstScanUpdate = Mutex<FirstScanUpdate?>(nil)

    private static func notify(_ event: FirstScanEvent) {
        firstScanUpdate.withLock { $0 }?(event)
    }

    /// Starts the first scan as a continued processing task. When the system rejects the request
    /// (for example, on an unsupported device), the scan runs in the app while it stays open.
    static func startFirstScan(services: AppServices, update: @escaping FirstScanUpdate) {
        firstScanUpdate.withLock { $0 = update }
        // Dynamic registration is allowed for continued processing tasks. Registering twice traps, so do it once.
        let registered = firstScanRegistered.withLock { done -> Bool in
            if !done {
                done = BGTaskScheduler.shared.register(forTaskWithIdentifier: AppInfo.firstScanTaskID, using: nil) { task in
                    guard let task = task as? BGContinuedProcessingTask else {
                        task.setTaskCompleted(success: false)
                        return
                    }
                    runFirstScan(task, services: services)
                }
            }
            return done
        }
        guard registered else { return runFirstScanInForeground(services: services) }

        let request = BGContinuedProcessingTaskRequest(
            identifier: AppInfo.firstScanTaskID,
            title: String(localized: "Finding your moments"),
            subtitle: String(localized: "Looking at recent photos on this iPhone")
        )
        // Fail instead of queueing: the user waits on screen, so a late start is worse than the fallback.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            runFirstScanInForeground(services: services)
        }
    }

    private static func runFirstScan(_ task: BGContinuedProcessingTask, services: AppServices) {
        nonisolated(unsafe) let task = task
        let stop = StopFlag()
        task.progress.totalUnitCount = 1
        task.progress.completedUnitCount = 0

        let work = Task {
            try await services.runFirstScan(shouldContinue: { !stop.isSet }) { p in
                // The system expires a task that shows no progress, so report every photo.
                task.progress.totalUnitCount = Int64(max(p.total, 1))
                task.progress.completedUnitCount = Int64(p.completed)
                task.updateTitle(
                    String(localized: "Finding your moments"),
                    subtitle: String(localized: "\(p.completed) of \(p.total) photos")
                )
                notify(.progress(p))
            }
        }
        task.expirationHandler = {
            stop.set()
            work.cancel()
        }
        Task {
            let outcome = try? await work.value
            let complete = outcome?.analysis.isComplete ?? false
            // Unfinished work continues in the charging task.
            if !complete { schedule() }
            notify(.finished(outcome?.suggestion, complete: complete))
            task.setTaskCompleted(success: complete)
        }
    }

    private static func runFirstScanInForeground(services: AppServices) {
        Task {
            let outcome = try? await services.runFirstScan { notify(.progress($0)) }
            let complete = outcome?.analysis.isComplete ?? false
            if !complete { schedule() }
            notify(.finished(outcome?.suggestion, complete: complete))
        }
    }
}

private final class StopFlag: Sendable {
    private let value = Mutex(false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}
#endif
