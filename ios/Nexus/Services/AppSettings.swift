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

    private init() {
        self.defaultCurrency = UserDefaults.standard.string(forKey: "defaultCurrency") ?? "AED"
        self.showCurrencyConversion = UserDefaults.standard.bool(forKey: "showCurrencyConversion")
        self.webhookBaseURL = UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"
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
