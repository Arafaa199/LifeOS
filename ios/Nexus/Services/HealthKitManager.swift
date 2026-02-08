import Foundation
import HealthKit
import Combine
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "healthkit")

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    enum PermissionStatus: String {
        case notSetUp
        case requested
        case working
        case failed
    }

    @Published var permissionStatus: PermissionStatus = .notSetUp
    @Published var lastSuccessfulHKQueryAt: Date?
    @Published var latestWeight: Double?
    @Published var latestWeightDate: Date?

    private let lastHKQueryKey = "healthkit_last_successful_query_at"

    var isAuthorized: Bool {
        permissionStatus == .working
    }

    var isSetUp: Bool {
        permissionStatus == .requested || permissionStatus == .working
    }

    // Quantity types (guaranteed to exist in HealthKit for these standard identifiers)
    private var weightType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var bodyFatType: HKQuantityType { HKQuantityType(.bodyFatPercentage) }
    private var hrvType: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }
    private var rhrType: HKQuantityType { HKQuantityType(.restingHeartRate) }
    private var respiratoryRateType: HKQuantityType { HKQuantityType(.respiratoryRate) }
    private var oxygenSatType: HKQuantityType { HKQuantityType(.oxygenSaturation) }
    private var stepsType: HKQuantityType { HKQuantityType(.stepCount) }
    private var activeCaloriesType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }

    // Category types
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    // Medication types (iOS 18+)
    // Note: Medications API requires iOS 18+ and uses per-object authorization
    // Access via HKObjectType.userAnnotatedMedicationType() and HKObjectType.medicationDoseEventType()

    private init() {
        lastSuccessfulHKQueryAt = UserDefaults.standard.object(forKey: lastHKQueryKey) as? Date
        checkAuthorization()
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func checkAuthorization() {
        guard isHealthDataAvailable else {
            permissionStatus = .failed
            return
        }

        // Apple hides read-permission status for privacy.
        // We use proof-of-access: if an HK query ever completed successfully
        // (tracked by lastSuccessfulHKQueryAt), we know access works.
        let hasCompletedAuth = UserDefaults.standard.bool(forKey: "healthKitAuthorizationRequested")
        if hasCompletedAuth {
            if lastSuccessfulHKQueryAt != nil {
                permissionStatus = .working
            } else {
                permissionStatus = .requested
            }
        } else {
            permissionStatus = .notSetUp
            Task {
                await verifyAndRequestAuthorizationIfNeeded()
            }
        }
    }

    private var leanBodyMassType: HKQuantityType { HKQuantityType(.leanBodyMass) }
    private var exerciseTimeType: HKQuantityType { HKQuantityType(.appleExerciseTime) }

    private var allReadTypes: Set<HKObjectType> {
        [
            weightType, bodyFatType,
            leanBodyMassType,
            hrvType, rhrType, heartRateType, respiratoryRateType, oxygenSatType,
            stepsType, activeCaloriesType,
            exerciseTimeType,
            sleepType,
            HKObjectType.workoutType()
        ]
    }

    private func verifyAndRequestAuthorizationIfNeeded() async {
        do {
            try await healthStore.requestAuthorization(toShare: [], read: allReadTypes)
            markAuthorizationCompleted()
            // Try a probe query immediately to establish proof-of-access
            await probeAndMarkAccess()
        } catch {
            permissionStatus = .failed
        }
    }

    /// Run a lightweight query to verify HealthKit access actually works.
    /// Sets permissionStatus = .working on success.
    private func probeAndMarkAccess() async {
        do {
            let _: HKQuantitySample? = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: self.stepsType,
                    predicate: nil,
                    limit: 1,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples?.first as? HKQuantitySample)
                    }
                }
                self.healthStore.execute(query)
            }
            // Query completed without error — access is working
            markQuerySuccess()
        } catch {
            logger.debug("Auth probe query failed (permissions may be denied): \(error.localizedDescription)")
        }
    }

    func markAuthorizationCompleted() {
        UserDefaults.standard.set(true, forKey: "healthKitAuthorizationRequested")
        permissionStatus = .requested
    }

    func markQuerySuccess() {
        lastSuccessfulHKQueryAt = Date()
        UserDefaults.standard.set(lastSuccessfulHKQueryAt, forKey: lastHKQueryKey)
        permissionStatus = .working
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: allReadTypes)
        markAuthorizationCompleted()
        await probeAndMarkAccess()
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

        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            throw HealthKitError.queryFailed("Failed to calculate start date")
        }
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
        guard let startDate = Calendar.current.date(byAdding: .hour, value: -24, to: endDate) else {
            throw HealthKitError.queryFailed("Failed to calculate start date")
        }
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

    // MARK: - Reauthorization

    enum ReauthResult {
        case prompted          // System dialog shown (.shouldRequest)
        case alreadyGranted    // .unnecessary + proof-of-access exists
        case likelyDenied      // .unnecessary + never had a successful query
    }

    func checkAndReauthorize() async throws -> ReauthResult {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        let status = try await healthStore.statusForAuthorizationRequest(toShare: [], read: allReadTypes)

        switch status {
        case .shouldRequest:
            try await healthStore.requestAuthorization(toShare: [], read: allReadTypes)
            markAuthorizationCompleted()
            await probeAndMarkAccess()
            return .prompted
        case .unnecessary:
            // Don't guess from lastSuccessfulHKQueryAt — actually probe
            await probeAndMarkAccess()
            if permissionStatus == .working {
                return .alreadyGranted
            } else {
                return .likelyDenied
            }
        default:
            try await healthStore.requestAuthorization(toShare: [], read: allReadTypes)
            markAuthorizationCompleted()
            await probeAndMarkAccess()
            return .prompted
        }
    }

    func syncAllToNexus() async throws -> [String: Bool] {
        var results: [String: Bool] = [:]

        // Sync weight
        do {
            if let (weight, _) = try await fetchLatestWeight() {
                do {
                    let response = try await NexusAPI.shared.logWeight(kg: weight)
                    results["weight"] = response.success
                    if !response.success {
                        logger.warning("[HealthKit] Weight sync returned success=false")
                    }
                } catch {
                    logger.error("[HealthKit] Weight sync failed: \(error.localizedDescription)")
                    results["weight"] = false
                }
            }
        } catch {
            logger.error("[HealthKit] Failed to fetch weight: \(error.localizedDescription)")
            results["weight"] = false
        }

        return results
    }

    // MARK: - Workouts

    /// Fetch and sync workouts from HealthKit to Nexus
    func syncWorkouts() async {
        guard isHealthDataAvailable else { return }

        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -7, to: endDate) ?? endDate

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        do {
            let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: HKObjectType.workoutType(),
                    predicate: predicate,
                    limit: 20,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let workouts = samples as? [HKWorkout] {
                        continuation.resume(returning: workouts)
                    } else {
                        continuation.resume(returning: [])
                    }
                }
                healthStore.execute(query)
            }

            // Sync each workout to Nexus
            for workout in workouts {
                await syncWorkoutToNexus(workout)
            }
        } catch {
            logger.debug("Workout sync query failed (non-critical): \(error.localizedDescription)")
        }
    }

    private func syncWorkoutToNexus(_ workout: HKWorkout) async {
        let workoutType = mapHKWorkoutType(workout.workoutActivityType)
        let durationMin = Int(workout.duration / 60)

        // Get calories if available
        var calories: Int?
        if let energyBurned = workout.totalEnergyBurned {
            calories = Int(energyBurned.doubleValue(for: .kilocalorie()))
        }

        // Get distance if available
        var distanceKm: Double?
        if let distance = workout.totalDistance {
            distanceKm = distance.doubleValue(for: .meterUnit(with: .kilo))
        }

        // Get heart rate stats if available
        var avgHr: Int?
        var maxHr: Int?
        if let stats = workout.statistics(for: HKQuantityType(.heartRate)) {
            if let avg = stats.averageQuantity() {
                avgHr = Int(avg.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            }
            if let max = stats.maximumQuantity() {
                maxHr = Int(max.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Dubai")

        let request = WorkoutLogRequest(
            date: nil,
            workoutType: workoutType,
            name: workout.workoutActivityType.name,
            durationMin: durationMin,
            caloriesBurned: calories,
            avgHr: avgHr,
            maxHr: maxHr,
            strain: nil,
            exercises: nil,
            distanceKm: distanceKm,
            notes: nil,
            source: "healthkit",
            startedAt: formatter.string(from: workout.startDate),
            endedAt: formatter.string(from: workout.endDate),
            externalId: workout.uuid.uuidString
        )

        do {
            _ = try await NexusAPI.shared.logWorkout(request)
        } catch {
            logger.debug("Individual workout sync failed (non-critical): \(error.localizedDescription)")
        }
    }

    private func mapHKWorkoutType(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return "strength"
        case .running:
            return "running"
        case .cycling:
            return "cycling"
        case .swimming:
            return "swimming"
        case .highIntensityIntervalTraining, .crossTraining:
            return "hiit"
        case .yoga, .pilates, .mindAndBody:
            return "yoga"
        case .walking:
            return "walking"
        case .rowing:
            return "rowing"
        case .elliptical, .stairClimbing:
            return "elliptical"
        case .dance:
            return "dance"
        case .martialArts, .boxing, .kickboxing:
            return "martial_arts"
        default:
            return "other"
        }
    }

    // MARK: - Medications (iOS 18+)
    // Note: HKMedicationDoseEvent API introduced in WWDC 2025
    // Backend schema and n8n webhook ready. iOS sync to be refined with device testing.

    struct MedicationDose: Sendable {
        let medicationId: String
        let doseEventId: String
        let medicationName: String
        let doseQuantity: Double?
        let doseUnit: String?
        let scheduledDate: Date
        let scheduledTime: Date?
        let takenAt: Date?
        let status: String  // scheduled, taken, skipped
    }

    /// Check if medications API is available
    /// Note: Requires iOS 18+ and user must have medications set up in Health app
    var isMedicationsAvailable: Bool {
        if #available(iOS 18.0, *) {
            return isHealthDataAvailable
        }
        return false
    }

    /// Request per-object authorization for medications (iOS 18+)
    @available(iOS 18.0, *)
    func requestMedicationAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }
        let medType = HKObjectType.userAnnotatedMedicationType()
        try await healthStore.requestPerObjectReadAuthorization(for: medType, predicate: nil)
    }

    /// Fetch medication dose events for a date range (iOS 18+)
    /// TODO: Implement once HKMedicationDoseEventQueryDescriptor API is documented
    @available(iOS 18.0, *)
    func fetchMedicationDoses(since startDate: Date) async throws -> [MedicationDose] {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        // Query all non-archived medications
        let descriptor = HKUserAnnotatedMedicationQueryDescriptor(
            predicate: HKQuery.predicateForUserAnnotatedMedications(isArchived: false)
        )

        let medications = try await descriptor.result(for: healthStore)
        var allDoses: [MedicationDose] = []

        // Parse each medication and its dose events
        // Note: Property names to be confirmed with device testing
        for medication in medications {
            // Access the underlying medication concept for name
            let medConcept = medication.medication
            let medId = medication.hashValue.description  // Unique per medication
            let medName = String(describing: medConcept)

            // Create a placeholder dose entry for each medication
            // Full dose event querying requires HKAnchoredObjectQuery
            let dose = MedicationDose(
                medicationId: medId,
                doseEventId: UUID().uuidString,
                medicationName: medName,
                doseQuantity: nil,
                doseUnit: nil,
                scheduledDate: Date(),
                scheduledTime: nil,
                takenAt: nil,
                status: "scheduled"
            )
            allDoses.append(dose)
        }

        return allDoses
    }
}

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case noData
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .noData:
            return "No health data found"
        case .queryFailed(let reason):
            return "Query failed: \(reason)"
        }
    }
}

// MARK: - HKWorkoutActivityType Extension

extension HKWorkoutActivityType {
    var name: String? {
        switch self {
        case .americanFootball: return "American Football"
        case .archery: return "Archery"
        case .australianFootball: return "Australian Football"
        case .badminton: return "Badminton"
        case .baseball: return "Baseball"
        case .basketball: return "Basketball"
        case .bowling: return "Bowling"
        case .boxing: return "Boxing"
        case .climbing: return "Climbing"
        case .cricket: return "Cricket"
        case .crossTraining: return "Cross Training"
        case .curling: return "Curling"
        case .cycling: return "Cycling"
        case .dance: return "Dance"
        case .elliptical: return "Elliptical"
        case .equestrianSports: return "Equestrian"
        case .fencing: return "Fencing"
        case .fishing: return "Fishing"
        case .functionalStrengthTraining: return "Functional Strength"
        case .golf: return "Golf"
        case .gymnastics: return "Gymnastics"
        case .handball: return "Handball"
        case .hiking: return "Hiking"
        case .hockey: return "Hockey"
        case .hunting: return "Hunting"
        case .lacrosse: return "Lacrosse"
        case .martialArts: return "Martial Arts"
        case .mindAndBody: return "Mind & Body"
        case .paddleSports: return "Paddle Sports"
        case .play: return "Play"
        case .pilates: return "Pilates"
        case .racquetball: return "Racquetball"
        case .rowing: return "Rowing"
        case .rugby: return "Rugby"
        case .running: return "Running"
        case .sailing: return "Sailing"
        case .skatingSports: return "Skating"
        case .snowSports: return "Snow Sports"
        case .soccer: return "Soccer"
        case .softball: return "Softball"
        case .squash: return "Squash"
        case .stairClimbing: return "Stair Climbing"
        case .surfingSports: return "Surfing"
        case .swimming: return "Swimming"
        case .tableTennis: return "Table Tennis"
        case .tennis: return "Tennis"
        case .trackAndField: return "Track & Field"
        case .traditionalStrengthTraining: return "Strength Training"
        case .volleyball: return "Volleyball"
        case .walking: return "Walking"
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .waterSports: return "Water Sports"
        case .wrestling: return "Wrestling"
        case .yoga: return "Yoga"
        case .barre: return "Barre"
        case .coreTraining: return "Core Training"
        case .crossCountrySkiing: return "Cross Country Skiing"
        case .downhillSkiing: return "Downhill Skiing"
        case .flexibility: return "Flexibility"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope: return "Jump Rope"
        case .kickboxing: return "Kickboxing"
        case .mixedCardio: return "Mixed Cardio"
        case .preparationAndRecovery: return "Recovery"
        case .snowboarding: return "Snowboarding"
        case .stairs: return "Stairs"
        case .stepTraining: return "Step Training"
        case .wheelchairWalkPace: return "Wheelchair Walk"
        case .wheelchairRunPace: return "Wheelchair Run"
        case .taiChi: return "Tai Chi"
        case .handCycling: return "Hand Cycling"
        case .discSports: return "Disc Sports"
        case .fitnessGaming: return "Fitness Gaming"
        default: return nil
        }
    }
}
