import Foundation
import HealthKit

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var latestWeight: Double?
    @Published var latestWeightDate: Date?

    // Quantity types
    private let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    private let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
    private let respiratoryRateType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!
    private let oxygenSatType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let activeCaloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

    // Category types
    private let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!

    private init() {
        checkAuthorization()
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func checkAuthorization() {
        guard isHealthDataAvailable else {
            isAuthorized = false
            return
        }

        let status = healthStore.authorizationStatus(for: weightType)
        isAuthorized = status == .sharingAuthorized
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        let typesToRead: Set<HKObjectType> = [
            // Body measurements
            weightType,
            bodyFatType,
            HKQuantityType.quantityType(forIdentifier: .leanBodyMass)!,

            // WHOOP / Heart data
            hrvType,
            rhrType,
            heartRateType,
            respiratoryRateType,
            oxygenSatType,

            // Activity
            stepsType,
            activeCaloriesType,
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!,

            // Sleep
            sleepType
        ]

        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
        checkAuthorization()
    }

    func fetchLatestWeight() async throws -> (weight: Double, date: Date)? {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
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

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: (weightKg, sample.endDate))
            }

            healthStore.execute(query)
        }
    }

    func fetchWeightHistory(days: Int = 30) async throws -> [(date: Date, weight: Double)] {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let weights = (samples as? [HKQuantitySample])?.map { sample in
                    (sample.endDate, sample.quantity.doubleValue(for: .gramUnit(with: .kilo)))
                } ?? []

                continuation.resume(returning: weights)
            }

            healthStore.execute(query)
        }
    }

    func syncLatestWeightToNexus() async throws -> Bool {
        guard let (weight, date) = try await fetchLatestWeight() else {
            return false
        }

        // Only sync if different from last synced
        if let lastWeight = latestWeight, let lastDate = latestWeightDate,
           abs(lastWeight - weight) < 0.01 && Calendar.current.isDate(lastDate, inSameDayAs: date) {
            return false
        }

        let response = try await NexusAPI.shared.logWeight(kg: weight)

        if response.success {
            latestWeight = weight
            latestWeightDate = date
            return true
        }

        return false
    }

    func fetchTodaysSteps() async throws -> Int {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }

            healthStore.execute(query)
        }
    }

    func fetchTodaysActiveCalories() async throws -> Int {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: activeCaloriesType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let calories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: Int(calories))
            }

            healthStore.execute(query)
        }
    }

    // MARK: - WHOOP / Recovery Data

    func fetchLatestHRV() async throws -> Double? {
        try await fetchLatestQuantity(type: hrvType, unit: .secondUnit(with: .milli))
    }

    func fetchLatestRHR() async throws -> Int? {
        guard let value = try await fetchLatestQuantity(type: rhrType, unit: .count().unitDivided(by: .minute())) else {
            return nil
        }
        return Int(value)
    }

    func fetchLatestRespiratoryRate() async throws -> Double? {
        try await fetchLatestQuantity(type: respiratoryRateType, unit: .count().unitDivided(by: .minute()))
    }

    func fetchLatestSpO2() async throws -> Double? {
        guard let value = try await fetchLatestQuantity(type: oxygenSatType, unit: .percent()) else {
            return nil
        }
        return value * 100 // Convert to percentage
    }

    func fetchLatestBodyFat() async throws -> Double? {
        guard let value = try await fetchLatestQuantity(type: bodyFatType, unit: .percent()) else {
            return nil
        }
        return value * 100 // Convert to percentage
    }

    private func fetchLatestQuantity(type: HKQuantityType, unit: HKUnit) async throws -> Double? {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Sleep Data (WHOOP + Apple Watch)

    struct SleepData {
        let date: Date
        let inBedStart: Date
        let inBedEnd: Date
        let totalInBedMinutes: Int
        let asleepMinutes: Int
        let remMinutes: Int
        let deepMinutes: Int
        let lightMinutes: Int
        let awakeMinutes: Int
        let sleepEfficiency: Double // asleep / inBed
    }

    func fetchLastNightSleep() async throws -> SleepData? {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        // Look back 24 hours for sleep data
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .hour, value: -24, to: endDate)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sleepSamples = samples as? [HKCategorySample], !sleepSamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // Aggregate sleep stages
                var inBedStart: Date?
                var inBedEnd: Date?
                var asleepMinutes = 0
                var remMinutes = 0
                var deepMinutes = 0
                var lightMinutes = 0  // core sleep
                var awakeMinutes = 0

                for sample in sleepSamples {
                    let duration = Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)

                    // Track overall in-bed time
                    if inBedStart == nil || sample.startDate < inBedStart! {
                        inBedStart = sample.startDate
                    }
                    if inBedEnd == nil || sample.endDate > inBedEnd! {
                        inBedEnd = sample.endDate
                    }

                    // Categorize by sleep stage
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        asleepMinutes += duration
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        lightMinutes += duration
                        asleepMinutes += duration
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deepMinutes += duration
                        asleepMinutes += duration
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        remMinutes += duration
                        asleepMinutes += duration
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awakeMinutes += duration
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        // Just in bed, not categorized
                        break
                    default:
                        break
                    }
                }

                guard let start = inBedStart, let end = inBedEnd else {
                    continuation.resume(returning: nil)
                    return
                }

                let totalInBed = Int(end.timeIntervalSince(start) / 60)
                let efficiency = totalInBed > 0 ? Double(asleepMinutes) / Double(totalInBed) : 0

                let sleepData = SleepData(
                    date: Calendar.current.startOfDay(for: end),
                    inBedStart: start,
                    inBedEnd: end,
                    totalInBedMinutes: totalInBed,
                    asleepMinutes: asleepMinutes,
                    remMinutes: remMinutes,
                    deepMinutes: deepMinutes,
                    lightMinutes: lightMinutes,
                    awakeMinutes: awakeMinutes,
                    sleepEfficiency: efficiency
                )

                continuation.resume(returning: sleepData)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Full Health Sync

    struct HealthSnapshot {
        let date: Date
        let weight: Double?
        let bodyFat: Double?
        let hrv: Double?
        let rhr: Int?
        let respiratoryRate: Double?
        let spo2: Double?
        let steps: Int
        let activeCalories: Int
        let sleep: SleepData?
    }

    func fetchTodaysSnapshot() async throws -> HealthSnapshot {
        async let weight = fetchLatestWeight()
        async let bodyFat = fetchLatestBodyFat()
        async let hrv = fetchLatestHRV()
        async let rhr = fetchLatestRHR()
        async let respRate = fetchLatestRespiratoryRate()
        async let spo2 = fetchLatestSpO2()
        async let steps = fetchTodaysSteps()
        async let calories = fetchTodaysActiveCalories()
        async let sleep = fetchLastNightSleep()

        return try await HealthSnapshot(
            date: Date(),
            weight: weight?.weight,
            bodyFat: bodyFat,
            hrv: hrv,
            rhr: rhr,
            respiratoryRate: respRate,
            spo2: spo2,
            steps: steps,
            activeCalories: calories,
            sleep: sleep
        )
    }

    func syncAllToNexus() async throws -> [String: Bool] {
        var results: [String: Bool] = [:]

        // Sync weight
        if let (weight, _) = try? await fetchLatestWeight() {
            let response = try? await NexusAPI.shared.logWeight(kg: weight)
            results["weight"] = response?.success ?? false
        }

        // TODO: Add sync for other metrics when webhooks are ready

        return results
    }
}

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case noData

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .noData:
            return "No health data found"
        }
    }
}
