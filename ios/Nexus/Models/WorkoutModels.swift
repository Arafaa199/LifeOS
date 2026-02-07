import Foundation
import HealthKit

// MARK: - Workout Model

struct Workout: Codable, Identifiable {
    let id: Int?
    let date: String
    let startedAt: String?
    let endedAt: String?
    let workoutType: String
    let name: String?
    let durationMin: Int?
    let caloriesBurned: Int?
    let avgHr: Int?
    let maxHr: Int?
    let strain: Double?
    let exercises: [WorkoutExercise]?
    let distanceKm: Double?
    let paceMinPerKm: Double?
    let notes: String?
    let source: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, date, name, strain, exercises, notes, source
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case workoutType = "workout_type"
        case durationMin = "duration_min"
        case caloriesBurned = "calories_burned"
        case avgHr = "avg_hr"
        case maxHr = "max_hr"
        case distanceKm = "distance_km"
        case paceMinPerKm = "pace_min_per_km"
        case createdAt = "created_at"
    }

    var displayDuration: String {
        guard let mins = durationMin else { return "" }
        if mins >= 60 {
            return "\(mins / 60)h \(mins % 60)m"
        }
        return "\(mins) min"
    }

    var typeIcon: String {
        switch workoutType.lowercased() {
        case "strength", "functional_strength", "traditional_strength":
            return "dumbbell.fill"
        case "running", "outdoor_run", "indoor_run", "treadmill":
            return "figure.run"
        case "cycling", "outdoor_cycle", "indoor_cycle", "spinning":
            return "bicycle"
        case "swimming", "pool_swim", "open_water_swim":
            return "figure.pool.swim"
        case "hiit", "cross_training", "crossfit":
            return "flame.fill"
        case "yoga", "pilates", "flexibility":
            return "figure.mind.and.body"
        case "walking", "outdoor_walk", "indoor_walk":
            return "figure.walk"
        case "rowing", "indoor_rowing":
            return "oar.2.crossed"
        case "elliptical", "stair_stepper":
            return "figure.stair.stepper"
        case "dance", "barre":
            return "figure.dance"
        case "martial_arts", "boxing", "kickboxing":
            return "figure.martial.arts"
        case "golf":
            return "figure.golf"
        case "tennis", "racquetball", "squash":
            return "figure.tennis"
        case "basketball", "soccer", "football":
            return "sportscourt.fill"
        default:
            return "figure.mixed.cardio"
        }
    }

    var typeDisplayName: String {
        workoutType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var sourceIcon: String {
        switch source?.lowercased() {
        case "healthkit", "apple_watch": return "applewatch"
        case "whoop": return "heart.circle.fill"
        case "manual", "app": return "hand.tap.fill"
        default: return "square.and.arrow.down"
        }
    }
}

struct WorkoutExercise: Codable {
    let name: String
    let sets: Int?
    let reps: Int?
    let weight: Double?
    let weightUnit: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, weight, notes
        case weightUnit = "weight_unit"
    }
}

// MARK: - API Responses

struct WorkoutsResponse: Codable {
    let workouts: [Workout]
    let weeklyStats: WeeklyWorkoutStats?
    let whoopToday: WhoopDayStrain?

    enum CodingKeys: String, CodingKey {
        case workouts
        case weeklyStats = "weekly_stats"
        case whoopToday = "whoop_today"
    }
}

struct WeeklyWorkoutStats: Codable {
    let workoutCount: Int
    let totalDuration: Int
    let totalCalories: Int
    let avgStrain: Double

    enum CodingKeys: String, CodingKey {
        case workoutCount = "workout_count"
        case totalDuration = "total_duration"
        case totalCalories = "total_calories"
        case avgStrain = "avg_strain"
    }
}

struct WhoopDayStrain: Codable {
    let dayStrain: Double?
    let avgHr: Int?
    let maxHr: Int?
    let caloriesActive: Int?

    enum CodingKeys: String, CodingKey {
        case dayStrain = "day_strain"
        case avgHr = "avg_hr"
        case maxHr = "max_hr"
        case caloriesActive = "calories_active"
    }
}

// MARK: - Request Models

struct WorkoutLogRequest: Codable {
    let date: String?
    let workoutType: String
    let name: String?
    let durationMin: Int?
    let caloriesBurned: Int?
    let avgHr: Int?
    let maxHr: Int?
    let strain: Double?
    let exercises: [WorkoutExercise]?
    let distanceKm: Double?
    let notes: String?
    let source: String
    let startedAt: String?
    let endedAt: String?
    let externalId: String?

    enum CodingKeys: String, CodingKey {
        case date, name, strain, exercises, notes, source
        case workoutType = "workout_type"
        case durationMin = "duration_min"
        case caloriesBurned = "calories_burned"
        case avgHr = "avg_hr"
        case maxHr = "max_hr"
        case distanceKm = "distance_km"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case externalId = "external_id"
    }
}

struct WorkoutLogResponse: Codable {
    let success: Bool
    let message: String?
    let data: WorkoutLogData?
}

struct WorkoutLogData: Codable {
    let workout: Workout?
    let weeklyStats: WeeklyWorkoutStats?

    enum CodingKeys: String, CodingKey {
        case workout
        case weeklyStats = "weekly_stats"
    }
}

// MARK: - Workout Types

enum WorkoutType: String, CaseIterable {
    case strength = "strength"
    case running = "running"
    case cycling = "cycling"
    case swimming = "swimming"
    case hiit = "hiit"
    case yoga = "yoga"
    case walking = "walking"
    case rowing = "rowing"
    case elliptical = "elliptical"
    case dance = "dance"
    case martialArts = "martial_arts"
    case other = "other"

    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiit: return "HIIT"
        case .yoga: return "Yoga"
        case .walking: return "Walking"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .dance: return "Dance"
        case .martialArts: return "Martial Arts"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .hiit: return "flame.fill"
        case .yoga: return "figure.mind.and.body"
        case .walking: return "figure.walk"
        case .rowing: return "oar.2.crossed"
        case .elliptical: return "figure.elliptical"
        case .dance: return "figure.dance"
        case .martialArts: return "figure.martial.arts"
        case .other: return "figure.mixed.cardio"
        }
    }

    // Map from HKWorkoutActivityType
    static func from(hkType: HKWorkoutActivityType) -> WorkoutType {
        switch hkType {
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return .strength
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .swimming:
            return .swimming
        case .highIntensityIntervalTraining, .crossTraining:
            return .hiit
        case .yoga, .pilates, .mindAndBody:
            return .yoga
        case .walking:
            return .walking
        case .rowing:
            return .rowing
        case .elliptical, .stairClimbing:
            return .elliptical
        case .dance:
            return .dance
        case .martialArts, .boxing, .kickboxing:
            return .martialArts
        default:
            return .other
        }
    }
}
