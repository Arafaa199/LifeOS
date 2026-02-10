import Foundation

// MARK: - Nutrition API Client

/// Handles food logging, water, fasting, meal confirmations
class NutritionAPI: BaseAPIClient {
    static let shared = NutritionAPI()

    private init() {
        super.init(category: "nutrition-api")
    }

    // MARK: - Food Logging

    func logFood(_ text: String, foodId: Int? = nil, mealType: String? = nil) async throws -> NexusResponse {
        let request = FoodLogRequest(text: text, food_id: foodId, meal_type: mealType)
        return try await post("/webhook/nexus-food-log", body: request)
    }

    func searchFoods(query: String, limit: Int = 10) async throws -> FoodSearchResponse {
        let path = buildPath("/webhook/nexus-food-search", query: ["q": query, "limit": "\(limit)"])
        return try await get(path)
    }

    func lookupBarcode(_ barcode: String) async throws -> FoodSearchResponse {
        let path = buildPath("/webhook/nexus-food-search", query: ["barcode": barcode])
        return try await get(path)
    }

    func fetchNutritionHistory(date: String? = nil) async throws -> NutritionHistoryResponse {
        let base = "/webhook/nexus-nutrition-history"
        let endpoint = date.map { buildPath(base, query: ["date": $0]) } ?? base
        return try await get(endpoint)
    }

    // MARK: - Fasting

    func startFast() async throws -> FastingResponse {
        struct EmptyBody: Encodable {}
        return try await post("/webhook/nexus-fast-start", body: EmptyBody())
    }

    func breakFast() async throws -> FastingResponse {
        struct EmptyBody: Encodable {}
        return try await post("/webhook/nexus-fast-break", body: EmptyBody())
    }

    func getFastingStatus() async throws -> FastingResponse {
        return try await get("/webhook/nexus-fast-status")
    }

    // MARK: - Meal Confirmation

    func fetchPendingMealConfirmations(date: Date? = nil) async throws -> [InferredMeal] {
        let base = "/webhook/nexus-pending-meals"
        let endpoint = date.map { buildPath(base, query: ["date": Self.dubaiDateString(from: $0)]) } ?? base

        struct Response: Codable {
            let meals: [InferredMeal]
        }

        let response: Response = try await get(endpoint)
        return response.meals
    }

    func confirmMeal(mealDate: String, mealTime: String, mealType: String, action: String) async throws -> NexusResponse {
        struct Request: Codable {
            let meal_date: String
            let meal_time: String
            let meal_type: String
            let action: String
        }

        let request = Request(
            meal_date: mealDate,
            meal_time: mealTime,
            meal_type: mealType,
            action: action
        )

        return try await post("/webhook/nexus-meal-confirmation", body: request)
    }
}
