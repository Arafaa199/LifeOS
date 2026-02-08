import Foundation
import os

@MainActor
final class NetworkConfig {
    static let shared = NetworkConfig()

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "network")
    private let userDefaultsKey = "webhookBaseURL"
    private let defaultBaseURL = "https://n8n.rfanw"

    private init() {}

    var baseURL: String {
        get {
            UserDefaults.standard.string(forKey: userDefaultsKey) ?? defaultBaseURL
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
        }
    }

    func url(for endpoint: String) -> URL? {
        let urlString = "\(baseURL)\(endpoint)"
        guard let url = URL(string: urlString) else {
            logger.error("Failed to construct URL from: \(urlString, privacy: .public)")
            return nil
        }
        return url
    }
}
