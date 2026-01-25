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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes

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
        scheduleHealthRefresh() // Schedule next refresh

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
        let healthKit = HealthKitManager.shared
        let storage = SharedStorage.shared

        guard healthKit.isHealthDataAvailable else {
            #if DEBUG
            print("[BackgroundTask] HealthKit not available")
            #endif
            return
        }

        do {
            // Sync weight to Nexus backend
            _ = try await healthKit.syncLatestWeightToNexus()
            #if DEBUG
            print("[BackgroundTask] Weight sync completed")
            #endif

            // Update widget with latest weight
            if let (weight, _) = try? await healthKit.fetchLatestWeight() {
                storage.saveDailySummary(
                    calories: storage.getTodayCalories(),
                    protein: storage.getTodayProtein(),
                    water: storage.getTodayWater(),
                    weight: weight
                )
            }

            // Fetch WHOOP data via API and update widget
            let sleepResponse = try await NexusAPI.shared.fetchSleepData()
            if let recovery = sleepResponse.data?.recovery,
               let score = recovery.recoveryScore {
                storage.saveRecoveryData(
                    score: score,
                    hrv: recovery.hrv,
                    rhr: recovery.rhr
                )
                #if DEBUG
                print("[BackgroundTask] Recovery data updated: \(score)%")
                #endif
            }
        } catch {
            #if DEBUG
            print("[BackgroundTask] Health sync failed: \(error)")
            #endif
        }
    }
}
