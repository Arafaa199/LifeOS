import SwiftUI

/// Shared color utilities to avoid duplication across views
enum ColorHelper {
    /// Returns color based on recovery score (WHOOP-style: green/yellow/red)
    static func recoveryColor(for score: Int) -> Color {
        switch score {
        case 67...100: return .nexusSuccess
        case 34...66: return .nexusFood  // Yellow/orange
        default: return .nexusError
        }
    }

    /// Returns color for log entry type
    static func color(for logType: LogType) -> Color {
        switch logType {
        case .food: return .nexusFood
        case .water: return .nexusWater
        case .weight: return .nexusWeight
        case .mood: return .nexusMood
        case .note: return .secondary
        case .other: return .secondary
        }
    }
}
