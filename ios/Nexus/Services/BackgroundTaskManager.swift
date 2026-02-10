import Foundation
import BackgroundTasks
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "background")

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    static let healthRefreshTaskIdentifier = "com.nexus.healthRefresh"

    private init() {}

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.healthRefreshTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                logger.error("Unexpected task type: \(type(of: task))")
                task.setTaskCompleted(success: false)
                return
            }
            self.handleHealthRefresh(task: refreshTask)
        }
    }

    func scheduleHealthRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.healthRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Health refresh scheduled")
        } catch {
            logger.error("Failed to schedule health refresh: \(error.localizedDescription)")
        }
    }

    private func handleHealthRefresh(task: BGAppRefreshTask) {
        scheduleHealthRefresh()

        let syncTask = Task { @MainActor in
            await self.performHealthSync()
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        Task {
            _ = await syncTask.result
            task.setTaskCompleted(success: true)
        }
    }

    @MainActor
    private func performHealthSync() async {
        let coordinator = SyncCoordinator.shared
        let storage = SharedStorage.shared

        await coordinator.syncForBackground()

        if let payload = coordinator.dashboardPayload,
           let recovery = payload.todayFacts?.recoveryScore {
            storage.saveRecoveryData(
                score: recovery,
                hrv: payload.todayFacts?.hrv,
                rhr: payload.todayFacts?.rhr
            )

            logger.debug("Recovery data updated: \(recovery)%")
        }

        if let weight = coordinator.dashboardPayload?.todayFacts?.weightKg {
            storage.saveDailySummary(
                calories: storage.getTodayCalories(),
                protein: storage.getTodayProtein(),
                water: storage.getTodayWater(),
                weight: weight
            )
        }
    }
}
