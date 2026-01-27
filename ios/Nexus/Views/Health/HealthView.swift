import SwiftUI
import Combine

struct HealthView: View {
    @StateObject private var viewModel = HealthViewModel()
    @State private var selectedSegment = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented Control
                Picker("", selection: $selectedSegment) {
                    Text("Today").tag(0)
                    Text("Trends").tag(1)
                    Text("Insights").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Content
                TabView(selection: $selectedSegment) {
                    HealthTodayView(viewModel: viewModel)
                        .tag(0)

                    HealthTrendsView(viewModel: viewModel)
                        .tag(1)

                    HealthInsightsView(viewModel: viewModel)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: HealthSourcesView(viewModel: viewModel)) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.nexusHealth)
                    }
                }
            }
        }
        .task {
            await viewModel.loadData()
        }
    }
}

// MARK: - Health ViewModel

@MainActor
class HealthViewModel: ObservableObject {
    @Published var dashboardPayload: DashboardPayload?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var dataSource: DataSourceInfo = .unknown

    // Health timeseries (for trends with daily data points)
    @Published var healthTimeseries: [DailyHealthPoint] = []
    @Published var hasTimeseriesData = false

    // HealthKit status
    @Published var healthKitAuthorized = false
    @Published var lastHealthKitSync: Date?
    @Published var healthKitSampleCount = 0

    // Error flags for data quality transparency
    @Published var timeseriesError = false
    @Published var healthKitSyncError = false

    private let dashboardService = DashboardService.shared
    private let healthKitManager = HealthKitManager.shared
    private let api = NexusAPI.shared

    enum DataSourceInfo {
        case network
        case cache
        case unknown

        var label: String {
            switch self {
            case .network: return "Live"
            case .cache: return "Cached"
            case .unknown: return ""
            }
        }
    }

    var todayFacts: TodayFacts? {
        dashboardPayload?.todayFacts
    }

    var healthFreshness: DomainFreshness? {
        dashboardPayload?.dataFreshness?.health
    }

    var serverHealthInsights: [RankedInsight] {
        let all = dashboardPayload?.dailyInsights?.rankedInsights ?? []
        return all.filter { insight in
            let t = insight.type.lowercased()
            return t.hasPrefix("recovery") || t.hasPrefix("sleep") || t.hasPrefix("weight") || t.hasPrefix("health") || t.hasPrefix("hrv") || t.hasPrefix("strain")
        }
    }

    var trends: [TrendPeriod] {
        dashboardPayload?.trends ?? []
    }

    var feedStatus: [FeedStatus] {
        dashboardPayload?.feedStatus ?? []
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        errorMessage = nil

        // Load dashboard and timeseries in parallel
        async let dashboardTask: () = loadDashboard()
        async let timeseriesTask: () = loadHealthTimeseries(days: 30)

        await dashboardTask
        await timeseriesTask

        // Check HealthKit status
        healthKitAuthorized = healthKitManager.isAuthorized
        let syncService = HealthKitSyncService.shared
        lastHealthKitSync = syncService.lastSyncDate
        healthKitSampleCount = syncService.lastSyncSampleCount

        isLoading = false
    }

    private func loadDashboard() async {
        do {
            let result = try await dashboardService.fetchDashboard()
            dashboardPayload = result.payload
            lastUpdated = result.lastUpdated
            dataSource = result.source == .network ? .network : .cache
        } catch {
            errorMessage = "Failed to load health data"
            // Try cached data
            if let cached = dashboardService.loadCached() {
                dashboardPayload = cached.payload
                lastUpdated = cached.lastUpdated
                dataSource = .cache
            }
        }
    }

    func loadHealthTimeseries(days: Int = 30) async {
        do {
            let response = try await api.fetchHealthTimeseries(days: days)
            if response.success, let data = response.data {
                healthTimeseries = data
                let daysWithData = data.filter { ($0.coverage ?? 0) > 0.1 }.count
                hasTimeseriesData = daysWithData >= 3
                timeseriesError = false
            }
        } catch {
            hasTimeseriesData = false
            timeseriesError = true
        }
    }

    func refreshHealthKit() async {
        let syncService = HealthKitSyncService.shared
        do {
            try await syncService.syncAllData()
            healthKitSyncError = false
        } catch {
            healthKitSyncError = true
        }
        lastHealthKitSync = syncService.lastSyncDate
        healthKitSampleCount = syncService.lastSyncSampleCount
    }

    // MARK: - Computed Insights

    func generateInsights() -> [HealthInsight] {
        // Prefer server-ranked insights for health
        let server = serverHealthInsights
        if !server.isEmpty {
            return server.prefix(3).map { ranked in
                HealthInsight(
                    title: ranked.type.replacingOccurrences(of: "_", with: " ").capitalized,
                    detail: ranked.description,
                    confidence: mapServerConfidence(ranked.confidence),
                    icon: iconForInsightType(ranked.type),
                    color: colorForInsightType(ranked.type)
                )
            }
        }

        // Fallback: client-side insights when server returns none
        guard let facts = todayFacts else { return [] }
        var insights: [HealthInsight] = []

        if let recovery = facts.recoveryScore,
           recovery > 70,
           let hrvVs7d = facts.hrvVs7d,
           hrvVs7d > 0 {
            insights.append(HealthInsight(
                title: "Recovery trending up",
                detail: "Your HRV is \(Int(hrvVs7d))% above your 7-day average. Good sleep pays off.",
                confidence: .moderate,
                icon: "heart.fill",
                color: .green
            ))
        }

        if let recovery = facts.recoveryScore,
           recovery < 40 {
            insights.append(HealthInsight(
                title: "Recovery is low today",
                detail: "Consider taking it easy. Low recovery often leads to impulsive decisions.",
                confidence: .moderate,
                icon: "exclamationmark.triangle",
                color: .orange
            ))
        }

        if let weightDelta = facts.weight30dDelta {
            if abs(weightDelta) < 0.5 {
                insights.append(HealthInsight(
                    title: "Weight stable",
                    detail: "Your weight has been consistent over the past 30 days (\(String(format: "%.1f", weightDelta)) kg change).",
                    confidence: .strong,
                    icon: "scalemass",
                    color: .blue
                ))
            } else if weightDelta > 2 {
                insights.append(HealthInsight(
                    title: "Weight trend up",
                    detail: "+\(String(format: "%.1f", weightDelta)) kg over 30 days. Check calorie logging accuracy.",
                    confidence: .early,
                    icon: "arrow.up.right",
                    color: .orange
                ))
            }
        }

        if let sleepVs7d = facts.sleepVs7d {
            if sleepVs7d < -15 {
                insights.append(HealthInsight(
                    title: "Sleep deficit building",
                    detail: "You're sleeping \(Int(abs(sleepVs7d)))% less than your 7-day average.",
                    confidence: .moderate,
                    icon: "bed.double",
                    color: .purple
                ))
            }
        }

        return Array(insights.prefix(3))
    }

    private func mapServerConfidence(_ confidence: String) -> HealthInsight.Confidence {
        switch confidence.lowercased() {
        case "strong", "high": return .strong
        case "moderate", "medium": return .moderate
        default: return .early
        }
    }

    private func iconForInsightType(_ type: String) -> String {
        let t = type.lowercased()
        if t.contains("sleep") { return "bed.double" }
        if t.contains("recovery") { return "heart.fill" }
        if t.contains("weight") { return "scalemass" }
        if t.contains("hrv") { return "waveform.path.ecg" }
        if t.contains("strain") { return "flame.fill" }
        return "lightbulb.fill"
    }

    private func colorForInsightType(_ type: String) -> Color {
        let t = type.lowercased()
        if t.contains("sleep") { return .purple }
        if t.contains("recovery") { return .green }
        if t.contains("weight") { return .blue }
        if t.contains("hrv") { return .teal }
        if t.contains("strain") { return .orange }
        return .yellow
    }
}

// MARK: - Insight Model

struct HealthInsight: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let confidence: Confidence
    let icon: String
    let color: Color

    enum Confidence: String {
        case early = "Early signal"
        case moderate = "Moderate"
        case strong = "Strong"

        var color: Color {
            switch self {
            case .early: return .orange
            case .moderate: return .blue
            case .strong: return .green
            }
        }
    }
}

#Preview {
    HealthView()
}
