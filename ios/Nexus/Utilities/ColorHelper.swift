import SwiftUI

/// Shared color utilities to avoid duplication across views
enum ColorHelper {
    /// Returns color based on recovery score (WHOOP-style: green/yellow/red)
    static func recoveryColor(for score: Int) -> Color {
        switch score {
        case 67...100: return NexusTheme.Colors.Semantic.green
        case 34...66: return NexusTheme.Colors.Semantic.amber
        default: return NexusTheme.Colors.Semantic.red
        }
    }

    /// Returns color for log entry type
    static func color(for logType: LogType) -> Color {
        switch logType {
        case .food: return NexusTheme.Colors.Semantic.amber
        case .water: return NexusTheme.Colors.Semantic.blue
        case .weight: return NexusTheme.Colors.Semantic.purple
        case .mood: return NexusTheme.Colors.accent
        case .note: return .secondary
        case .other: return .secondary
        }
    }
}
