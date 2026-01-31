import Testing
@testable import Nexus

// MARK: - Model Validation Tests

@Suite("Request Model Validation")
struct RequestValidationTests {
    
    @Test("Water log validates amount range")
    func waterValidation() async throws {
        // Valid amounts should succeed
        _ = try WaterLogRequest(amount_ml: 250)
        _ = try WaterLogRequest(amount_ml: 1)
        _ = try WaterLogRequest(amount_ml: 10000)
        
        // Invalid amounts should throw
        #expect(throws: ValidationError.self) {
            try WaterLogRequest(amount_ml: 0)
        }
        
        #expect(throws: ValidationError.self) {
            try WaterLogRequest(amount_ml: -100)
        }
        
        #expect(throws: ValidationError.self) {
            try WaterLogRequest(amount_ml: 15000)
        }
    }
    
    @Test("Weight log validates weight range")
    func weightValidation() async throws {
        // Valid weights should succeed
        _ = try WeightLogRequest(weight_kg: 70.5)
        _ = try WeightLogRequest(weight_kg: 1.0)
        _ = try WeightLogRequest(weight_kg: 500.0)
        
        // Invalid weights should throw
        #expect(throws: ValidationError.self) {
            try WeightLogRequest(weight_kg: 0)
        }
        
        #expect(throws: ValidationError.self) {
            try WeightLogRequest(weight_kg: -50)
        }
        
        #expect(throws: ValidationError.self) {
            try WeightLogRequest(weight_kg: 600)
        }
    }
    
    @Test("Mood log validates mood and energy range")
    func moodValidation() async throws {
        // Valid values should succeed
        _ = try MoodLogRequest(mood: 5, energy: 7)
        _ = try MoodLogRequest(mood: 1, energy: 1)
        _ = try MoodLogRequest(mood: 10, energy: 10)
        
        // Invalid mood values should throw
        #expect(throws: ValidationError.self) {
            try MoodLogRequest(mood: 0, energy: 5)
        }
        
        #expect(throws: ValidationError.self) {
            try MoodLogRequest(mood: 11, energy: 5)
        }
        
        // Invalid energy values should throw
        #expect(throws: ValidationError.self) {
            try MoodLogRequest(mood: 5, energy: 0)
        }
        
        #expect(throws: ValidationError.self) {
            try MoodLogRequest(mood: 5, energy: 11)
        }
    }
}

@Suite("Daily Summary Tests")
struct DailySummaryTests {
    
    @Test("Daily summary equality")
    func summaryEquality() async throws {
        let summary1 = DailySummary(
            totalCalories: 2000,
            totalProtein: 120,
            totalWater: 2500,
            latestWeight: 75.5
        )
        
        let summary2 = DailySummary(
            totalCalories: 2000,
            totalProtein: 120,
            totalWater: 2500,
            latestWeight: 75.5
        )
        
        let summary3 = DailySummary(
            totalCalories: 1800,
            totalProtein: 120,
            totalWater: 2500,
            latestWeight: 75.5
        )
        
        #expect(summary1 == summary2)
        #expect(summary1 != summary3)
    }
    
    @Test("Weight property backward compatibility")
    func weightPropertyAlias() async throws {
        var summary = DailySummary()
        
        // Setting through latestWeight
        summary.latestWeight = 80.0
        #expect(summary.weight == 80.0)
        
        // Setting through weight alias
        summary.weight = 85.0
        #expect(summary.latestWeight == 85.0)
        #expect(summary.weight == 85.0)
    }
    
    @Test("Daily summary default values")
    func defaultValues() async throws {
        let summary = DailySummary()
        
        #expect(summary.totalCalories == 0)
        #expect(summary.totalProtein == 0)
        #expect(summary.totalWater == 0)
        #expect(summary.latestWeight == nil)
        #expect(summary.mood == nil)
        #expect(summary.energy == nil)
    }
}

@Suite("Log Type Tests")
struct LogTypeTests {
    
    @Test("Log type icons are correct")
    func logTypeIcons() async throws {
        #expect(LogType.food.icon == "fork.knife")
        #expect(LogType.water.icon == "drop.fill")
        #expect(LogType.weight.icon == "scalemass.fill")
        #expect(LogType.mood.icon == "face.smiling.fill")
        #expect(LogType.note.icon == "note.text")
        #expect(LogType.other.icon == "questionmark.circle")
    }
    
    @Test("Log type colors are correct")
    func logTypeColors() async throws {
        #expect(LogType.food.color == "orange")
        #expect(LogType.water.color == "blue")
        #expect(LogType.weight.color == "green")
        #expect(LogType.mood.color == "purple")
        #expect(LogType.note.color == "gray")
        #expect(LogType.other.color == "secondary")
    }
}

@Suite("Validation Error Tests")
struct ValidationErrorTests {
    
    @Test("Validation error descriptions")
    func errorDescriptions() async throws {
        let waterError = ValidationError.invalidWaterAmount
        #expect(waterError.errorDescription?.contains("Water") == true)
        
        let weightError = ValidationError.invalidWeight
        #expect(weightError.errorDescription?.contains("Weight") == true)
        
        let moodError = ValidationError.invalidMoodOrEnergy
        #expect(moodError.errorDescription?.contains("Mood") == true)
    }
    
    @Test("Validation error recovery suggestions")
    func recoverySuggestions() async throws {
        let error = ValidationError.invalidWaterAmount
        #expect(error.recoverySuggestion != nil)
        #expect(error.recoverySuggestion?.contains("valid") == true)
    }
}

// MARK: - Codable Tests

@Suite("Model Serialization")
struct ModelSerializationTests {
    
    @Test("Food request encodes correctly")
    func foodRequestEncoding() async throws {
        let request = FoodLogRequest(text: "chicken breast")
        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(FoodLogRequest.self, from: encoded)
        
        #expect(decoded.text == "chicken breast")
        #expect(decoded.source == "ios")
    }
    
    @Test("Nexus response decodes correctly")
    func responseDecoding() async throws {
        let json = """
        {
            "success": true,
            "message": "Food logged",
            "data": {
                "calories": 165,
                "protein": 31.0,
                "total_water_ml": null,
                "weight_kg": null
            }
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(NexusResponse.self, from: json)
        
        #expect(response.success == true)
        #expect(response.message == "Food logged")
        #expect(response.data?.calories == 165)
        #expect(response.data?.protein == 31.0)
    }
    
    @Test("Sync status response decodes correctly")
    func syncStatusDecoding() async throws {
        let json = """
        {
            "success": true,
            "domains": [
                {
                    "domain": "health",
                    "last_success_at": "2024-01-01T12:00:00Z",
                    "last_success_rows": 10,
                    "last_success_duration_ms": 150,
                    "last_success_source": "ios",
                    "last_error_at": null,
                    "last_error": null,
                    "running_count": 0,
                    "freshness": "current",
                    "seconds_since_success": 60
                }
            ],
            "timestamp": "2024-01-01T12:01:00Z"
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(SyncStatusResponse.self, from: json)
        
        #expect(response.success == true)
        #expect(response.domains?.count == 1)
        #expect(response.domains?.first?.domain == "health")
        #expect(response.domains?.first?.last_success_rows == 10)
    }
}
