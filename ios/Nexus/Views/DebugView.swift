import SwiftUI

struct DebugView: View {
    @State private var logs: [DebugLog] = []
    @State private var apiEntries: [APIDebugLog.Entry] = []
    @State private var isTestingWHOOP = false
    @State private var isTestingSummary = false
    @State private var isTestingFinance = false
    @State private var expandedEntryId: UUID?
    @State private var refreshTimer: Timer?

    var body: some View {
        List {
            // API Call History
            Section("API Calls (\(apiEntries.count))") {
                if apiEntries.isEmpty {
                    Text("No API calls recorded yet.")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(apiEntries) { entry in
                        apiEntryRow(entry)
                    }
                }
            }

            // API Tests Section
            Section("API Tests") {
                Button(action: testWHOOPEndpoint) {
                    HStack {
                        Image(systemName: "bed.double.fill")
                            .foregroundColor(NexusTheme.Colors.Semantic.purple)
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
                            .foregroundColor(NexusTheme.Colors.Semantic.blue)
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
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
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
                    Image(systemName: KeychainManager.shared.hasAPIKey ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(KeychainManager.shared.hasAPIKey ? .green : .red)
                }

                let diag = CircuitBreaker.shared.diagnostics
                LabeledContent("Circuit Breaker") {
                    Text(diag.state.rawValue)
                        .foregroundColor(diag.state == .closed ? .green : .red)
                }
            }

            // Manual Test Logs
            if !logs.isEmpty {
                Section("Test Logs (\(logs.count))") {
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
                Button("Refresh API Log") {
                    refreshAPIEntries()
                }

                Button("Clear All", role: .destructive) {
                    logs.removeAll()
                    APIDebugLog.shared.clear()
                    apiEntries.removeAll()
                }

                Button("Copy API Log to Clipboard") {
                    let text = apiEntries.map { entry in
                        let status = entry.statusCode.map { "\($0)" } ?? "ERR"
                        return "[\(formatTime(entry.timestamp))] \(entry.method) \(entry.url) -> \(status) (\(entry.durationMs)ms, \(entry.responseSize)B)"
                    }.joined(separator: "\n")
                    UIPasteboard.general.string = text
                }
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshAPIEntries() }
        .onDisappear { refreshTimer?.invalidate() }
    }

    // MARK: - API Entry Row

    @ViewBuilder
    private func apiEntryRow(_ entry: APIDebugLog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 6) {
                // Status badge
                Text(entry.statusCode.map { "\($0)" } ?? "ERR")
                    .font(.caption2.weight(.bold).monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor(entry).opacity(0.15))
                    .foregroundColor(statusColor(entry))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Method
                Text(entry.method)
                    .font(.caption.weight(.semibold).monospaced())

                Spacer()

                // Duration + Size
                Text("\(entry.durationMs)ms")
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)

                Text(formatBytes(entry.responseSize))
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }

            // URL path (truncated)
            if let urlPath = URL(string: entry.url)?.path {
                Text(urlPath)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Timestamp
            Text(formatTime(entry.timestamp))
                .font(.caption2)
                .foregroundColor(Color(.tertiaryLabel))

            // Expandable response preview
            if expandedEntryId == entry.id {
                if let preview = entry.responsePreview {
                    Text(preview.prefix(1000))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(20)
                        .textSelection(.enabled)
                        .padding(8)
                        .background(NexusTheme.Colors.cardAlt)
                        .cornerRadius(6)
                }
                if let body = entry.requestBody {
                    Text("Request: \(body.prefix(500))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(NexusTheme.Colors.Semantic.amber)
                        .lineLimit(10)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedEntryId = expandedEntryId == entry.id ? nil : entry.id
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(_ entry: APIDebugLog.Entry) -> Color {
        guard let code = entry.statusCode else { return .red }
        switch code {
        case 200..<300: return .green
        case 300..<400: return .orange
        default: return .red
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        return String(format: "%.1fKB", Double(bytes) / 1024)
    }

    private func refreshAPIEntries() {
        apiEntries = APIDebugLog.shared.entries
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
                    refreshAPIEntries()
                }
            } catch {
                await MainActor.run {
                    addLog("WHOOP Error", "Exception: \(error.localizedDescription)\n\nFull error: \(error)", isError: true)
                    isTestingWHOOP = false
                    refreshAPIEntries()
                }
            }
        }
    }

    private func testDailySummary() {
        isTestingSummary = true
        addLog("Summary Test", "Starting request to /webhook/nexus-dashboard-today...")

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
                    refreshAPIEntries()
                }
            } catch {
                await MainActor.run {
                    addLog("Summary Error", "Exception: \(error.localizedDescription)\n\nFull error: \(error)", isError: true)
                    isTestingSummary = false
                    refreshAPIEntries()
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
                    refreshAPIEntries()
                }
            } catch {
                await MainActor.run {
                    addLog("Finance Error", "Exception: \(error.localizedDescription)\n\nFull error: \(error)", isError: true)
                    isTestingFinance = false
                    refreshAPIEntries()
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
