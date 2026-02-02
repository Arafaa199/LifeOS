import Foundation
import SwiftUI

/// App-wide constants to avoid magic numbers throughout the codebase
enum Constants {
    // MARK: - API
    enum API {
        static let defaultBaseURL = "https://n8n.rfanw"
        static let maxRetries = 3
        static let initialRetryDelay: TimeInterval = 0.5
        static let requestTimeout: TimeInterval = 30
    }

    // MARK: - Time Intervals (in seconds)
    enum Time {
        static let oneMinute: Foundation.TimeInterval = 60
        static let oneHour: Foundation.TimeInterval = 3600
        static let oneDay: Foundation.TimeInterval = 86400
        static let oneWeek: Foundation.TimeInterval = 604800

        static let backgroundRefreshInterval: Foundation.TimeInterval = 30 * 60  // 30 minutes
        static let staleDataThreshold: Foundation.TimeInterval = 60 * 60  // 1 hour
    }

    // MARK: - Finance
    enum Finance {
        static let duplicateToleranceDays = 1
        static let recurringDailyMaxDays = 10
        static let recurringWeeklyMaxDays = 35
        static let recurringMonthlyMaxDays = 100
    }

    // MARK: - Image Processing
    enum Image {
        static let maxDimension: CGFloat = 1024
        static let maxSizeKB = 500
        static let compressionQuality: CGFloat = 0.8
    }

    // MARK: - UI Opacity
    enum Opacity {
        static let subtle: Double = 0.08
        static let light: Double = 0.1
        static let medium: Double = 0.12
        static let normal: Double = 0.15
        static let prominent: Double = 0.3
        static let offlineBanner: Double = 0.85
    }

    // MARK: - UI Dimensions
    enum Dimensions {
        static let cardCornerRadius: CGFloat = 12
        static let largeCornerRadius: CGFloat = 16
        static let iconSize: CGFloat = 24
        static let largeIconSize: CGFloat = 40
        static let chartHeight: CGFloat = 150
        static let recoveryCircleSize: CGFloat = 140
    }

    // MARK: - Animation
    enum AnimationDuration {
        static let defaultDuration: Foundation.TimeInterval = 0.2
        static let springDuration: Foundation.TimeInterval = 0.5
    }

    // MARK: - Dubai Timezone
    enum Dubai {
        static let timeZone = TimeZone(identifier: "Asia/Dubai")!

        static var calendar: Calendar {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            return cal
        }

        static func iso8601String(from date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = timeZone
            return formatter.string(from: date)
        }

        static func dateString(from date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = timeZone
            return formatter.string(from: date)
        }

        static func isDateInToday(_ date: Date) -> Bool {
            calendar.isDateInToday(date)
        }
    }

    // MARK: - Health Data
    enum Health {
        static let weightHistoryDays = 30
        static let sleepHistoryDays = 7
        static let recoveryGreenThreshold = 67
        static let recoveryYellowThreshold = 34
    }
}

// MARK: - Data Extension for Safe String Conversion

extension Data {
    /// Safely append string data with UTF-8 encoding
    /// Note: UTF-8 encoding only fails for invalid Unicode, which won't happen with ASCII HTTP headers
    mutating func appendString(_ string: String) {
        guard let data = string.data(using: .utf8) else {
            assertionFailure("Failed to encode string to UTF-8: \(string)")
            return
        }
        append(data)
    }
}
