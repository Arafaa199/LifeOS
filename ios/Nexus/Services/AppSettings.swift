import Foundation
import SwiftUI
import Combine

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var defaultCurrency: String {
        didSet { UserDefaults.standard.set(defaultCurrency, forKey: "defaultCurrency") }
    }
    @Published var showCurrencyConversion: Bool {
        didSet { UserDefaults.standard.set(showCurrencyConversion, forKey: "showCurrencyConversion") }
    }
    @Published var webhookBaseURL: String {
        didSet { UserDefaults.standard.set(webhookBaseURL, forKey: "webhookBaseURL") }
    }

    @Published var whoopSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(whoopSyncEnabled, forKey: "whoopSyncEnabled") }
    }
    @Published var financeSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(financeSyncEnabled, forKey: "financeSyncEnabled") }
    }
    @Published var healthKitSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(healthKitSyncEnabled, forKey: "healthKitSyncEnabled") }
    }
    @Published var calendarSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarSyncEnabled, forKey: "calendarSyncEnabled") }
    }
    @Published var documentsSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(documentsSyncEnabled, forKey: "documentsSyncEnabled") }
    }

    private init() {
        self.defaultCurrency = UserDefaults.standard.string(forKey: "defaultCurrency") ?? "AED"
        self.showCurrencyConversion = UserDefaults.standard.bool(forKey: "showCurrencyConversion")
        self.webhookBaseURL = UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"

        // Domain sync flags default to true (object_forKey returns nil for unset keys)
        self.whoopSyncEnabled = UserDefaults.standard.object(forKey: "whoopSyncEnabled") as? Bool ?? true
        self.financeSyncEnabled = UserDefaults.standard.object(forKey: "financeSyncEnabled") as? Bool ?? true
        self.healthKitSyncEnabled = UserDefaults.standard.object(forKey: "healthKitSyncEnabled") as? Bool ?? true
        self.calendarSyncEnabled = UserDefaults.standard.object(forKey: "calendarSyncEnabled") as? Bool ?? true
        self.documentsSyncEnabled = UserDefaults.standard.object(forKey: "documentsSyncEnabled") as? Bool ?? true
    }

    // Currency display helpers
    static let supportedCurrencies = ["AED", "USD", "EUR", "GBP", "SAR"]

    static func currencySymbol(for code: String) -> String {
        switch code {
        case "AED": return "AED"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "SAR": return "SAR"
        default: return code
        }
    }
}

// MARK: - Global Currency Formatting

/// Formats a currency amount with the appropriate symbol.
/// AED/SAR show code after amount, others show symbol before.
func formatCurrency(_ amount: Double, currency: String) -> String {
    let absAmount = abs(amount)
    let isNegative = amount < 0
    let prefix = isNegative ? "-" : ""

    switch currency {
    case "AED", "SAR":
        // Show currency code after amount: "150.00 AED"
        return "\(prefix)\(String(format: "%.2f", absAmount)) \(currency)"
    case "USD":
        return "\(prefix)$\(String(format: "%.2f", absAmount))"
    case "EUR":
        return "\(prefix)€\(String(format: "%.2f", absAmount))"
    case "GBP":
        return "\(prefix)£\(String(format: "%.2f", absAmount))"
    default:
        return "\(prefix)\(String(format: "%.2f", absAmount)) \(currency)"
    }
}
