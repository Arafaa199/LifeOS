import Foundation
import HealthKit
import Combine
import UIKit

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
        if let weightResult = try? await syncLatestWeight() {
            if weightResult { syncedCount += 1 }
        }

        // Fetch samples from the last sync date or last 7 days
        let startDate = lastSyncDate ?? Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        async let samples = fetchQuantitySamples(since: startDate)
        async let sleep = fetchSleepSamples(since: startDate)
        async let workouts = fetchWorkoutSamples(since: startDate)

        let (quantitySamples, sleepSamples, workoutSamples) = try await (samples, sleep, workouts)

        let totalCount = quantitySamples.count + sleepSamples.count + workoutSamples.count

        // Try batch sync if we have non-weight samples
        if totalCount > 0 {
            let payload = HealthKitBatchPayload(
                client_id: UUID().uuidString,
                device: await UIDevice.current.name,
                source_bundle_id: Bundle.main.bundleIdentifier ?? "com.rfanw.nexus",
                captured_at: ISO8601DateFormatter().string(from: Date()),
                samples: quantitySamples,
                workouts: workoutSamples,
                sleep: sleepSamples
            )

            // Try batch sync but don't fail if it errors - weight sync is more important
            if let response = try? await sendToWebhook(payload), response.success {
                syncedCount += totalCount
            }
        }

        // Mark sync as successful if we synced anything
        if syncedCount > 0 {
            lastSyncDate = Date()
            lastSyncSampleCount = syncedCount
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
        }
    }

    // MARK: - Direct Weight Sync (uses working /nexus-weight endpoint)

    private func syncLatestWeight() async throws -> Bool {
        let weightType = HKQuantityType(.bodyMass)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let sample: HKQuantitySample? = try await withCheckedThrowingContinuation { continuation in
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
            healthStore.execute(query)
        }

        guard let weightSample = sample else { return false }

        let weightKg = weightSample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        let response = try await NexusAPI.shared.logWeight(kg: weightKg)
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

        return try await withCheckedThrowingContinuation { continuation in
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

                let results = (samples as? [HKQuantitySample])?.map { sample in
                    HealthKitSample(
                        sample_id: sample.uuid.uuidString,
                        type: identifier,
                        value: sample.quantity.doubleValue(for: unit),
                        unit: unit.unitString,
                        start_date: ISO8601DateFormatter().string(from: sample.startDate),
                        end_date: ISO8601DateFormatter().string(from: sample.endDate)
                    )
                } ?? []

                continuation.resume(returning: results)
            }

            healthStore.execute(query)
        }
    }

    private func fetchSleepSamples(since startDate: Date) async throws -> [HealthKitSleepSample] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 100,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let results = (samples as? [HKCategorySample])?.compactMap { sample -> HealthKitSleepSample? in
                    guard let stage = HealthKitSyncService.sleepStageStringStatic(for: sample.value) else { return nil }

                    return HealthKitSleepSample(
                        sleep_id: sample.uuid.uuidString,
                        stage: stage,
                        start_date: ISO8601DateFormatter().string(from: sample.startDate),
                        end_date: ISO8601DateFormatter().string(from: sample.endDate)
                    )
                } ?? []

                continuation.resume(returning: results)
            }

            healthStore.execute(query)
        }
    }

    private func fetchWorkoutSamples(since startDate: Date) async throws -> [HealthKitWorkoutSample] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
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

                let results: [HealthKitWorkoutSample] = (samples as? [HKWorkout])?.map { workout in
                    // Extract calories from statistics if available
                    let energyType = HKQuantityType(.activeEnergyBurned)
                    let calories = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())

                    return HealthKitWorkoutSample(
                        workout_id: workout.uuid.uuidString,
                        type: "HKWorkoutActivityType\(workout.workoutActivityType.rawValue)",
                        duration_min: workout.duration / 60.0,
                        calories: calories,
                        distance_m: workout.totalDistance?.doubleValue(for: .meter()),
                        start_date: ISO8601DateFormatter().string(from: workout.startDate),
                        end_date: ISO8601DateFormatter().string(from: workout.endDate)
                    )
                } ?? []

                continuation.resume(returning: results)
            }

            healthStore.execute(query)
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
        let baseURL = UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"
        guard let url = URL(string: "\(baseURL)/webhook/healthkit/batch") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = UserDefaults.standard.string(forKey: "nexusAPIKey") {
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
