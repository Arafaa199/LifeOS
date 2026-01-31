import Foundation
import BackgroundTasks

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    static let healthRefreshTaskIdentifier = "com.nexus.healthRefresh"

    private init() {}

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.healthRefreshTaskIdentifier,
            using: nil
        ) { task in
            self.handleHealthRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleHealthRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.healthRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[BackgroundTask] Health refresh scheduled")
            #endif
        } catch {
            #if DEBUG
            print("[BackgroundTask] Failed to schedule health refresh: \(error)")
            #endif
        }
    }

    private func handleHealthRefresh(task: BGAppRefreshTask) {
        scheduleHealthRefresh()

        let syncTask = Task {
            await performHealthSync()
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

            #if DEBUG
            print("[BackgroundTask] Recovery data updated from coordinator: \(recovery)%")
            #endif
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
