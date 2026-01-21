import Foundation

/// Shared time formatting utilities to avoid duplication across views
enum TimeFormatter {
    /// Formats minutes into "Xh Ym" or "Xm" format
    static func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    /// Formats minutes into duration string (alias for formatMinutes)
    static func formatDuration(_ minutes: Int) -> String {
        formatMinutes(minutes)
    }

    /// Formats seconds into "Xh Ym Zs" format
    static func formatSeconds(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    /// Formats a date to relative time (e.g., "5 min ago", "2 hrs ago")
    static func formatTimeAgo(_ date: Date) -> String {
        let minutes = Int(-date.timeIntervalSinceNow / 60)
        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes) min ago"
        } else {
            let hours = minutes / 60
            return hours == 1 ? "1 hr ago" : "\(hours) hrs ago"
        }
    }
}
