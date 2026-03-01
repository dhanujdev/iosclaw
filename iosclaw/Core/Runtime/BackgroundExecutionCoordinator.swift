import BackgroundTasks
import Foundation

final class BackgroundExecutionCoordinator {
    static let refreshTaskIdentifier = "com.iosclaw.agent.refresh"

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            self.handle(refreshTask) { }
        }
    }

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("Background refresh scheduling failed: \(error)")
            #endif
        }
    }

    func handle(_ task: BGAppRefreshTask, action: @escaping @Sendable () async -> Void) {
        scheduleRefresh()

        let worker = Task {
            await action()
            if !Task.isCancelled {
                task.setTaskCompleted(success: true)
            }
        }

        task.expirationHandler = {
            worker.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
