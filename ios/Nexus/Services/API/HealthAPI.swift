import Foundation

// MARK: - Health API Client

/// Handles health logging: weight, mood, workouts, supplements
class HealthAPI: BaseAPIClient {
    static let shared = HealthAPI()

    private init() {
        super.init(category: "health-api")
    }

    // MARK: - Weight

    func logWeight(kg: Double) async throws -> NexusResponse {
        let request = try WeightLogRequest(weight_kg: kg)
        return try await post("/webhook/nexus-weight", body: request)
    }

    // MARK: - Mood

    func logMood(mood: Int, energy: Int, notes: String? = nil) async throws -> NexusResponse {
        let request = try MoodLogRequest(mood: mood, energy: energy, notes: notes)
        return try await post("/webhook/nexus-mood", body: request)
    }

    // MARK: - Universal Log

    func logUniversal(_ text: String) async throws -> NexusResponse {
        let request = UniversalLogRequest(text: text)
        return try await post("/webhook/nexus-universal", body: request)
    }

    // MARK: - Workouts

    func fetchWorkouts() async throws -> WorkoutsResponse {
        try await get("/webhook/nexus-workouts")
    }

    func logWorkout(_ request: WorkoutLogRequest) async throws -> WorkoutLogResponse {
        try await post("/webhook/nexus-workout", body: request)
    }

    // MARK: - Supplements

    func fetchSupplements() async throws -> SupplementsResponse {
        try await get("/webhook/nexus-supplements")
    }

    func createSupplement(_ request: SupplementCreateRequest) async throws -> SupplementUpsertResponse {
        try await post("/webhook/nexus-supplement", body: request)
    }

    func updateSupplement(id: Int, request: SupplementCreateRequest) async throws -> SupplementUpsertResponse {
        struct UpdateRequest: Codable {
            let id: Int
            let name: String
            let brand: String?
            let doseAmount: Double?
            let doseUnit: String?
            let frequency: String
            let timesOfDay: [String]
            let category: String
            let notes: String?

            enum CodingKeys: String, CodingKey {
                case id, name, brand, frequency, category, notes
                case doseAmount = "dose_amount"
                case doseUnit = "dose_unit"
                case timesOfDay = "times_of_day"
            }
        }
        let updateReq = UpdateRequest(
            id: id,
            name: request.name,
            brand: request.brand,
            doseAmount: request.doseAmount,
            doseUnit: request.doseUnit,
            frequency: request.frequency,
            timesOfDay: request.timesOfDay,
            category: request.category,
            notes: request.notes
        )
        return try await post("/webhook/nexus-supplement", body: updateReq)
    }

    func logSupplementDose(_ request: SupplementLogRequest) async throws -> SupplementLogResponse {
        try await post("/webhook/nexus-supplement-log", body: request)
    }

    func deactivateSupplement(id: Int) async throws -> NexusResponse {
        struct DeactivateRequest: Codable {
            let id: Int
            let active: Bool
        }
        return try await post("/webhook/nexus-supplement", body: DeactivateRequest(id: id, active: false))
    }

    // MARK: - Medications

    func createMedication(_ request: MedicationCreateRequest) async throws -> MedicationCreateResponse {
        return try await post("/webhook/nexus-medication-create", body: request)
    }

    // MARK: - BJJ Sessions

    func logBJJSession(_ request: LogBJJRequest) async throws -> BJJLogResponse {
        try await post("/webhook/nexus-bjj-log", body: request)
    }

    func fetchBJJHistory(limit: Int = 20, offset: Int = 0) async throws -> BJJHistoryResponse {
        let path = buildPath("/webhook/nexus-bjj-history", query: [
            "limit": "\(limit)",
            "offset": "\(offset)"
        ])
        return try await get(path)
    }

    func fetchBJJStreak() async throws -> BJJStreakResponse {
        try await get("/webhook/nexus-bjj-streak")
    }

    func updateBJJSession(_ request: BJJUpdateRequest) async throws -> BJJLogResponse {
        try await post("/webhook/nexus-bjj-update", body: request)
    }

    func deleteBJJSession(id: Int) async throws -> BJJDeleteResponse {
        struct DeleteRequest: Codable { let id: Int }
        return try await post("/webhook/nexus-bjj-delete", body: DeleteRequest(id: id))
    }
}
