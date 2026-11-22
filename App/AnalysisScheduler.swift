#if os(iOS)
import BackgroundTasks
import Foundation
import Synchronization

/// Schedules on-device analysis while the phone charges. No network is needed.
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
            // The checkpoint keeps finished photos, so an early stop is still a success.
            task.setTaskCompleted(success: true)
        }
    }
}

private final class StopFlag: Sendable {
    private let value = Mutex(false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}
#endif
