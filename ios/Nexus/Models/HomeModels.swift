import Foundation

// MARK: - Home Status Response

struct HomeStatusResponse: Codable {
    let success: Bool
    let home: HomeStatus?
    let lastUpdated: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, home, error
        case lastUpdated = "last_updated"
    }
}

struct HomeStatus: Codable {
    let lights: [String: LightState]?
    let switches: [String: SwitchState]?
    let vacuum: VacuumState?
    let camera: CameraState?
    let presence: PresenceState?
}

// MARK: - Device States

struct LightState: Codable {
    let entityId: String
    let state: String
    let brightness: Int?
    let brightnessPct: Int?

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state, brightness
        case brightnessPct = "brightness_pct"
    }

    var isOn: Bool { state == "on" }
    var isAvailable: Bool { state != "unavailable" }
}

struct SwitchState: Codable {
    let entityId: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
    }

    var isOn: Bool { state == "on" }
    var isAvailable: Bool { state != "unavailable" }
}

struct VacuumState: Codable {
    let entityId: String
    let state: String
    let battery: Int?
    let fanSpeed: String?

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state, battery
        case fanSpeed = "fan_speed"
    }

    var isDocked: Bool { state == "docked" }
    var isCleaning: Bool { state == "cleaning" }
    var isReturning: Bool { state == "returning" }

    var stateDisplay: String {
        switch state {
        case "docked": return "Docked"
        case "cleaning": return "Cleaning"
        case "returning": return "Returning"
        case "paused": return "Paused"
        case "idle": return "Idle"
        case "error": return "Error"
        default: return state.capitalized
        }
    }
}

struct CameraState: Codable {
    let entityId: String
    let state: String
    let sleeping: Bool

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state, sleeping
    }

    var isActive: Bool { !sleeping && state != "unavailable" }

    var stateDisplay: String {
        if sleeping { return "Sleep" }
        if state == "unavailable" { return "Offline" }
        return "Active"
    }
}

struct PresenceState: Codable {
    let home: Bool
    let lastMotion: String?
    let motionLocation: String?

    enum CodingKeys: String, CodingKey {
        case home
        case lastMotion = "last_motion"
        case motionLocation = "motion_location"
    }
}

// MARK: - Convenience Extensions

extension HomeStatus {
    var monitorsOn: Bool {
        let left = switches?["left_monitor"]?.isOn ?? false
        let right = switches?["right_monitor"]?.isOn ?? false
        return left || right
    }

    var monitorCount: (on: Int, total: Int) {
        let left = switches?["left_monitor"]?.isOn ?? false
        let right = switches?["right_monitor"]?.isOn ?? false
        let on = (left ? 1 : 0) + (right ? 1 : 0)
        return (on, 2)
    }

    var lightsOn: Bool {
        lights?.values.contains { $0.isOn } ?? false
    }

    var printerOn: Bool {
        switches?["printer"]?.isOn ?? false
    }

    var anyDeviceOn: Bool {
        lightsOn || monitorsOn || printerOn
    }
}
