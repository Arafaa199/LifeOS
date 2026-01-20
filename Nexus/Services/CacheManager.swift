import Foundation

class CacheManager {
    static let shared = CacheManager()

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default

    private var cacheDirectory: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NexusCache")
    }

    private init() {
        createCacheDirectory()
    }

    private func createCacheDirectory() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Generic Cache Methods

    func save<T: Codable>(_ object: T, forKey key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let encoded = try? encoder.encode(object) {
            let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
            try? encoded.write(to: fileURL)

            // Save timestamp
            defaults.set(Date(), forKey: "\(key)_timestamp")
        }
    }

    func load<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(T.self, from: data)
    }

    func getCacheAge(forKey key: String) -> TimeInterval? {
        guard let timestamp = defaults.object(forKey: "\(key)_timestamp") as? Date else {
            return nil
        }
        return Date().timeIntervalSince(timestamp)
    }

    func isCacheValid(forKey key: String, maxAge: TimeInterval = 300) -> Bool {
        guard let age = getCacheAge(forKey: key) else {
            return false
        }
        return age < maxAge
    }

    func delete(forKey key: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        try? fileManager.removeItem(at: fileURL)
        defaults.removeObject(forKey: "\(key)_timestamp")
    }

    func clearAll() {
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }

        // Clear all cache timestamps
        for key in defaults.dictionaryRepresentation().keys where key.hasSuffix("_timestamp") {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Finance-Specific Cache

    func saveFinanceSummary(_ summary: FinanceSummary, transactions: [Transaction]) {
        save(summary, forKey: "finance_summary")
        save(transactions, forKey: "finance_transactions")
    }

    func loadFinanceCache() -> (summary: FinanceSummary?, transactions: [Transaction]?) {
        let summary = load(FinanceSummary.self, forKey: "finance_summary")
        let transactions = load([Transaction].self, forKey: "finance_transactions")
        return (summary, transactions)
    }

    func saveBudgets(_ budgets: [Budget]) {
        save(budgets, forKey: "finance_budgets")
    }

    func loadBudgets() -> [Budget]? {
        return load([Budget].self, forKey: "finance_budgets")
    }
}
