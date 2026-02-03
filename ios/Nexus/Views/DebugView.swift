import SwiftUI

struct DebugView: View {
    @State private var logs: [DebugLog] = []
    @State private var isTestingWHOOP = false
    @State private var isTestingSummary = false
    @State private var isTestingFinance = false

    var body: some View {
        List {
            // API Tests Section
            Section("API Tests") {
                Button(action: testWHOOPEndpoint) {
                    HStack {
                        Image(systemName: "bed.double.fill")
                            .foregroundColor(.indigo)
                        Text("Test WHOOP Sleep API")
                        Spacer()
                        if isTestingWHOOP {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isTestingWHOOP)

                Button(action: testDailySummary) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.blue)
                        Text("Test Daily Summary API")
                        Spacer()
                        if isTestingSummary {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isTestingSummary)

                Button(action: testFinanceAPI) {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.green)
                        Text("Test Finance API")
                        Spacer()
                        if isTestingFinance {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isTestingFinance)
            }

            // Config Section
            Section("Configuration") {
                LabeledContent("Base URL") {
                    Text(NetworkConfig.shared.baseURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                LabeledContent("API Key Set") {
                    Image(systemName: UserDefaults.standard.string(forKey: "nexusAPIKey") != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(UserDefaults.standard.string(forKey: "nexusAPIKey") != nil ? .green : .red)
                }
            }

            // Logs Section
            Section("Logs (\(logs.count))") {
                if logs.isEmpty {
                    Text("No logs yet. Run a test above.")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: log.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundColor(log.isError ? .red : .green)
                                    .font(.caption)
                                Text(log.title)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(log.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Text(log.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(10)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Actions
            Section {
                Button("Clear Logs", role: .destructive) {
                    logs.removeAll()
                }

                Button("Copy Logs to Clipboard") {
                    let text = logs.map { "[\($0.timestamp)] \($0.title): \($0.message)" }.joined(separator: "\n\n")
                    UIPasteboard.general.string = text
                }
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - API Tests

    private func testWHOOPEndpoint() {
        isTestingWHOOP = true
        addLog("WHOOP Test", "Starting request to /webhook/nexus-sleep...")

        Task {
            do {
                let response = try await NexusAPI.shared.fetchSleepData()
                await MainActor.run {
                    if response.success {
                        if let data = response.data {
                            var details = "Date: \(data.date)\n"
                            if let recovery = data.recovery {
                                details += "Recovery: \(recovery.recoveryScore ?? 0)%\n"
                                details += "HRV: \(recovery.hrv ?? 0) ms\n"
                                details += "RHR: \(recovery.rhr ?? 0) bpm\n"
                            } else {
                                details += "Recovery: nil\n"
                            }
                            if let sleep = data.sleep {
                                details += "Sleep: \(sleep.totalSleepMin) min\n"
                                details += "Deep: \(sleep.deepSleepMin ?? 0) min\n"
                            } else {
                                details += "Sleep: nil\n"
                            }
                            addLog("WHOOP Success", details, isError: false)
                        } else {
                            addLog("WHOOP Warning", "Response success but data is nil", isError: true)
                        }
                    } else {
                        addLog("WHOOP Failed", "API returned success: false", isError: true)
                    }
                    isTestingWHOOP = false
                }
            } catch {
                await MainActor.run {
                    addLog("WHOOP Error", "Exception: \(error.localizedDescription)\n\nFull error: \(error)", isError: true)
                    isTestingWHOOP = false
                }
            }
        }
    }

    private func testDailySummary() {
        isTestingSummary = true
        addLog("Summary Test", "Starting request to /webhook/nexus-summary...")

        Task {
            do {
                let response = try await NexusAPI.shared.fetchDailySummary()
                await MainActor.run {
                    if response.success {
                        if let data = response.data {
                            let details = """
                            Date: \(data.date)
                            Calories: \(data.calories)
                            Protein: \(data.protein)g
                            Water: \(data.water)ml
                            Weight: \(data.weight ?? 0)kg
                            """
                            addLog("Summary Success", details, isError: false)
                        } else {
                            addLog("Summary Warning", "Response success but data is nil", isError: true)
                        }
                    } else {
                        addLog("Summary Failed", "API returned success: false", isError: true)
                    }
                    isTestingSummary = false
                }
            } catch {
                await MainActor.run {
                    addLog("Summary Error", "Exception: \(error.localizedDescription)\n\nFull error: \(error)", isError: true)
                    isTestingSummary = false
                }
            }
        }
    }

    private func testFinanceAPI() {
        isTestingFinance = true
        addLog("Finance Test", "Starting request to /webhook/nexus-finance-summary...")

        Task {
            do {
                let response = try await NexusAPI.shared.fetchFinanceSummary()
                await MainActor.run {
                    if response.success {
                        if let data = response.data {
                            let details = """
                            Total Spent: \(data.totalSpent ?? 0)
                            Grocery: \(data.grocerySpent ?? 0)
                            Eating Out: \(data.eatingOutSpent ?? 0)
                            Transactions: \(data.recentTransactions?.count ?? 0)
                            """
                            addLog("Finance Success", details, isError: false)
                        } else {
                            addLog("Finance Warning", "Response success but data is nil", isError: true)
                        }
                    } else {
                        addLog("Finance Failed", "API returned success: false", isError: true)
                    }
                    isTestingFinance = false
                }
            } catch {
                await MainActor.run {
                    addLog("Finance Error", "Exception: \(error.localizedDescription)\n\nFull error: \(error)", isError: true)
                    isTestingFinance = false
                }
            }
        }
    }

    // MARK: - Logging

    private func addLog(_ title: String, _ message: String, isError: Bool = false) {
        let log = DebugLog(title: title, message: message, isError: isError)
        logs.insert(log, at: 0)
    }
}

// MARK: - Debug Log Model

struct DebugLog: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let isError: Bool
    let timestamp = Date()
}

#Preview {
    NavigationStack {
        DebugView()
    }
}
