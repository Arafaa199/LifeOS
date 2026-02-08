import Foundation
import HealthKit
import Combine
import UIKit
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "healthkit-sync")

@MainActor
class HealthKitSyncService: ObservableObject {
    static let shared = HealthKitSyncService()

    private let healthStore = HKHealthStore()

    @Published var lastSyncDate: Date?
    @Published var lastSyncSampleCount: Int = 0
    @Published var isSyncing: Bool = false

    private let userDefaults = UserDefaults.standard
    private let lastSyncKey = "healthkit_last_sync_date"

    private init() {
        lastSyncDate = userDefaults.object(forKey: lastSyncKey) as? Date
    }

    // MARK: - Public Sync Methods

    func syncAllData() async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var syncedCount = 0

        // IMPORTANT: Sync weight directly via the working /nexus-weight endpoint
        // The batch endpoint has issues, but weight sync works via individual endpoint
        do {
            if try await syncLatestWeight() { syncedCount += 1 }
        } catch {
            logger.error("Weight sync failed: \(error.localizedDescription)")
        }

        // Fetch samples from the last sync date or last 7 days
        let startDate = lastSyncDate ?? Constants.Dubai.calendar.date(byAdding: .day, value: -7, to: Date())!

        // Fetch each category independently — one failure shouldn't block others
        var quantitySamples: [HealthKitSample] = []
        var sleepSamples: [HealthKitSleepSample] = []
        var workoutSamples: [HealthKitWorkoutSample] = []
        var successfulQueries = 0

        do {
            quantitySamples = try await fetchQuantitySamples(since: startDate)
            successfulQueries += 1
        } catch {
            logger.error("Failed to fetch quantity samples: \(error.localizedDescription)")
        }

        do {
            sleepSamples = try await fetchSleepSamples(since: startDate)
            successfulQueries += 1
        } catch {
            logger.error("Failed to fetch sleep samples: \(error.localizedDescription)")
        }

        do {
            workoutSamples = try await fetchWorkoutSamples(since: startDate)
            successfulQueries += 1
        } catch {
            logger.error("Failed to fetch workout samples: \(error.localizedDescription)")
        }

        // Only mark query success if at least one query actually succeeded
        if successfulQueries > 0 {
            HealthKitManager.shared.markQuerySuccess()
        } else {
            logger.warning("All HealthKit queries failed — not marking query success")
        }

        let totalCount = quantitySamples.count + sleepSamples.count + workoutSamples.count

        // Try batch sync if we have non-weight samples
        if totalCount > 0 {
            let payload = HealthKitBatchPayload(
                client_id: UUID().uuidString,
                device: UIDevice.current.name,
                source_bundle_id: Bundle.main.bundleIdentifier ?? "com.rfanw.nexus",
                captured_at: Constants.Dubai.iso8601String(from: Date()),
                samples: quantitySamples,
                workouts: workoutSamples,
                sleep: sleepSamples
            )

            // Try batch sync but don't fail if it errors - weight sync is more important
            do {
                let response = try await sendToWebhook(payload)
                if response.success {
                    syncedCount += totalCount
                } else {
                    logger.warning("Batch webhook returned success=false, \(totalCount) samples not confirmed")
                }
            } catch {
                logger.error("Batch webhook failed for \(totalCount) samples: \(error.localizedDescription)")
            }
        }

        // Sync medications (iOS 18+)
        if #available(iOS 18.0, *) {
            do {
                // Request per-object authorization if not already granted
                try await HealthKitManager.shared.requestMedicationAuthorization()
                let medicationCount = try await syncMedications()
                if medicationCount > 0 {
                    syncedCount += medicationCount
                    logger.info("Synced \(medicationCount) medication doses")
                }
            } catch {
                // Medications are optional — don't fail the whole sync
                logger.warning("Medications sync skipped: \(error.localizedDescription)")
            }
        }

        // Mark sync as successful if we synced anything
        if syncedCount > 0 {
            lastSyncDate = Date()
            lastSyncSampleCount = syncedCount
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        }
    }

    // MARK: - Timeout Helper for Continuation-Based Queries

    /// Wraps async operations with a timeout to prevent indefinite hangs if callbacks never fire
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Direct Weight Sync (uses working /nexus-weight endpoint)

    private func syncLatestWeight() async throws -> Bool {
        let weightType = HKQuantityType(.bodyMass)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let sample: HKQuantitySample? = try await withTimeout(seconds: 30) {
            try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: weightType,
                    predicate: nil,
                    limit: 1,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: samples?.first as? HKQuantitySample)
                }
                self.healthStore.execute(query)
            }
        }

        guard let weightSample = sample else { return false }

        let weightKg = weightSample.quantity.doubleValue(for: .gramUnit(with: .kilo))

        // Validate weight is within acceptable range
        guard let validatedWeight = HealthKitValueValidator.validateWeight(weightKg) else {
            return false
        }

        let response = try await NexusAPI.shared.logWeight(kg: validatedWeight)
        return response.success
    }

    // MARK: - Fetch Methods

    private func fetchQuantitySamples(since startDate: Date) async throws -> [HealthKitSample] {
        var samples: [HealthKitSample] = []

        // Define quantity types to sync
        let types: [(HKQuantityType, String, HKUnit)] = [
            (HKQuantityType(.heartRateVariabilitySDNN), "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", .secondUnit(with: .milli)),
            (HKQuantityType(.restingHeartRate), "HKQuantityTypeIdentifierRestingHeartRate", .count().unitDivided(by: .minute())),
            (HKQuantityType(.activeEnergyBurned), "HKQuantityTypeIdentifierActiveEnergyBurned", .kilocalorie()),
            (HKQuantityType(.stepCount), "HKQuantityTypeIdentifierStepCount", .count()),
            (HKQuantityType(.bodyMass), "HKQuantityTypeIdentifierBodyMass", .gramUnit(with: .kilo))
        ]

        for (type, identifier, unit) in types {
            let typeSamples = try await fetchSamplesForType(type, identifier: identifier, unit: unit, since: startDate)
            samples.append(contentsOf: typeSamples)
        }

        return samples
    }

    private func fetchSamplesForType(_ type: HKQuantityType, identifier: String, unit: HKUnit, since startDate: Date) async throws -> [HealthKitSample] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withTimeout(seconds: 30) {
            try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: 100, // Limit to last 100 samples per type
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let results: [HealthKitSample] = (samples as? [HKQuantitySample])?.compactMap { sample -> HealthKitSample? in
                        let rawValue = sample.quantity.doubleValue(for: unit)

                        // Validate the metric value is within acceptable range
                        guard let validatedValue = HealthKitValueValidator.validateQuantitySample(rawValue, typeIdentifier: identifier) else {
                            return nil
                        }

                        return HealthKitSample(
                            sample_id: sample.uuid.uuidString,
                            type: identifier,
                            value: validatedValue,
                            unit: unit.unitString,
                            start_date: Constants.Dubai.iso8601String(from: sample.startDate),
                            end_date: Constants.Dubai.iso8601String(from: sample.endDate)
                        )
                    } ?? []

                    continuation.resume(returning: results)
                }

                self.healthStore.execute(query)
            }
        }
    }

    private func fetchSleepSamples(since startDate: Date) async throws -> [HealthKitSleepSample] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withTimeout(seconds: 30) {
            try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: sleepType,
                    predicate: predicate,
                    limit: 100,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let results = (samples as? [HKCategorySample])?.compactMap { sample -> HealthKitSleepSample? in
                        guard let stage = HealthKitSyncService.sleepStageStringStatic(for: sample.value) else { return nil }

                        // Validate sleep duration (in minutes)
                        let durationMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                        guard HealthKitValueValidator.validateSleep(durationMinutes) != nil else {
                            return nil
                        }

                        return HealthKitSleepSample(
                            sleep_id: sample.uuid.uuidString,
                            stage: stage,
                            start_date: Constants.Dubai.iso8601String(from: sample.startDate),
                            end_date: Constants.Dubai.iso8601String(from: sample.endDate)
                        )
                    } ?? []

                    continuation.resume(returning: results)
                }

                self.healthStore.execute(query)
            }
        }
    }

    private func fetchWorkoutSamples(since startDate: Date) async throws -> [HealthKitWorkoutSample] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withTimeout(seconds: 30) {
            try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: HKWorkoutType.workoutType(),
                    predicate: predicate,
                    limit: 50,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let results: [HealthKitWorkoutSample] = (samples as? [HKWorkout])?.compactMap { workout in
                        // Validate workout duration (max 24 hours / 1440 minutes)
                        let durationMinutes = workout.duration / 60.0
                        guard HealthKitValueValidator.validateSleep(durationMinutes) != nil else {
                            // Duration is too long, skip this workout
                            return nil
                        }

                        // Extract calories from statistics if available
                        let energyType = HKQuantityType(.activeEnergyBurned)
                        var calories = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())

                        // Validate calories are reasonable (must be non-negative and not exceed 10000 kcal in a single session)
                        if let calorieValue = calories, calorieValue < 0 || calorieValue > 10000 {
                            logger.warning("Invalid calorie reading for workout filtered: \(calorieValue, privacy: .public) kcal (valid range: 0-10000 kcal)")
                            calories = nil
                        }

                        return HealthKitWorkoutSample(
                            workout_id: workout.uuid.uuidString,
                            type: "HKWorkoutActivityType\(workout.workoutActivityType.rawValue)",
                            duration_min: durationMinutes,
                            calories: calories,
                            distance_m: workout.totalDistance?.doubleValue(for: .meter()),
                            start_date: Constants.Dubai.iso8601String(from: workout.startDate),
                            end_date: Constants.Dubai.iso8601String(from: workout.endDate)
                        )
                    } ?? []

                    continuation.resume(returning: results)
                }

                self.healthStore.execute(query)
            }
        }
    }

    // MARK: - Helper Methods

    nonisolated private static func sleepStageStringStatic(for value: Int) -> String? {
        switch value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            return "inBed"
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return "asleep"
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return "awake"
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            return "core"
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            return "deep"
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return "rem"
        default:
            return nil
        }
    }

    private func sendToWebhook(_ payload: HealthKitBatchPayload) async throws -> HealthKitSyncResponse {
        guard let url = NetworkConfig.shared.url(for: "/webhook/healthkit/batch") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = KeychainManager.shared.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(HealthKitSyncResponse.self, from: data)
    }

    // MARK: - Medications Sync (iOS 18+)

    @available(iOS 18.0, *)
    func syncMedications() async throws -> Int {
        // Fetch medications from HealthKit
        let startDate = lastSyncDate ?? Constants.Dubai.calendar.date(byAdding: .day, value: -7, to: Date())!
        let doses = try await HealthKitManager.shared.fetchMedicationDoses(since: startDate)

        if doses.isEmpty { return 0 }

        // Convert to API format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        let samples = doses.map { dose in
            HealthKitMedicationSample(
                medication_id: dose.medicationId,
                dose_event_id: dose.doseEventId,
                medication_name: dose.medicationName,
                dose_quantity: dose.doseQuantity,
                dose_unit: dose.doseUnit,
                scheduled_date: dateFormatter.string(from: dose.scheduledDate),
                scheduled_time: dose.scheduledTime.map { timeFormatter.string(from: $0) },
                taken_at: dose.takenAt.map { Constants.Dubai.iso8601String(from: $0) },
                status: dose.status
            )
        }

        let payload = MedicationsBatchPayload(
            client_id: UUID().uuidString,
            device: UIDevice.current.name,
            source_bundle_id: Bundle.main.bundleIdentifier ?? "com.rfanw.nexus",
            captured_at: Constants.Dubai.iso8601String(from: Date()),
            medications: samples
        )

        let response = try await sendMedicationsToWebhook(payload)
        return response.success ? samples.count : 0
    }

    @available(iOS 18.0, *)
    private func sendMedicationsToWebhook(_ payload: MedicationsBatchPayload) async throws -> MedicationsSyncResponse {
        guard let url = NetworkConfig.shared.url(for: "/webhook/medications/batch") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = KeychainManager.shared.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(MedicationsSyncResponse.self, from: data)
    }
}

// MARK: - Payload Models

struct HealthKitBatchPayload: Codable {
    let client_id: String
    let device: String
    let source_bundle_id: String
    let captured_at: String
    let samples: [HealthKitSample]
    let workouts: [HealthKitWorkoutSample]
    let sleep: [HealthKitSleepSample]
}

struct MedicationsBatchPayload: Codable {
    let client_id: String
    let device: String
    let source_bundle_id: String
    let captured_at: String
    let medications: [HealthKitMedicationSample]
}

struct HealthKitSample: Codable {
    let sample_id: String
    let type: String
    let value: Double
    let unit: String
    let start_date: String
    let end_date: String
}

struct HealthKitWorkoutSample: Codable {
    let workout_id: String
    let type: String
    let duration_min: Double
    let calories: Double?
    let distance_m: Double?
    let start_date: String
    let end_date: String
}

struct HealthKitSleepSample: Codable {
    let sleep_id: String
    let stage: String
    let start_date: String
    let end_date: String
}

struct HealthKitMedicationSample: Codable {
    let medication_id: String
    let dose_event_id: String
    let medication_name: String
    let dose_quantity: Double?
    let dose_unit: String?
    let scheduled_date: String
    let scheduled_time: String?
    let taken_at: String?
    let status: String
}

struct HealthKitSyncResponse: Codable {
    let success: Bool
    let inserted: InsertedCounts?
    let timestamp: String?

    struct InsertedCounts: Codable {
        let samples: Int
        let workouts: Int
        let sleep: Int
    }
}

struct MedicationsSyncResponse: Codable {
    let success: Bool
    let inserted: MedicationsInsertedCounts?
    let timestamp: String?

    struct MedicationsInsertedCounts: Codable {
        let medications: Int
    }
}
