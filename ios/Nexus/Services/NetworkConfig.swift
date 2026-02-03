import Foundation

@MainActor
final class NetworkConfig {
    static let shared = NetworkConfig()

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
        URL(string: "\(baseURL)\(endpoint)")
    }
}
