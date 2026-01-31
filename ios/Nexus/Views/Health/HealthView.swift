import SwiftUI
import Combine

struct HealthView: View {
    @StateObject private var viewModel = HealthViewModel()
    @State private var selectedSegment = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    Text("Today").tag(0)
                    Text("Trends").tag(1)
                    Text("Insights").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)

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

// MARK: - Timeseries State

enum TimeseriesState: Equatable {
    case idle
    case loading
    case loaded([DailyHealthPoint])
    case failed(String)

    var data: [DailyHealthPoint] {
        if case .loaded(let points) = self { return points }
        return []
    }

    var hasData: Bool {
        if case .loaded(let points) = self {
            return points.filter { ($0.coverage ?? 0) > 0.1 }.count >= 3
        }
        return false
    }

    static func == (lhs: TimeseriesState, rhs: TimeseriesState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading): return true
        case (.loaded(let a), .loaded(let b)): return a.count == b.count
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Health ViewModel

@MainActor
class HealthViewModel: ObservableObject {
    @Published var dashboardPayload: DashboardPayload?
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var dataSource: DataSourceInfo = .unknown

    // Health timeseries (typed state replaces boolean flags)
    @Published var timeseriesState: TimeseriesState = .idle

    // HealthKit status
    @Published var healthKitAuthorized = false
    @Published var lastHealthKitSync: Date?
    @Published var healthKitSampleCount = 0

    // Direct HealthKit readings (local, no server round-trip)
    @Published var localWeight: Double?
    @Published var localWeightDate: Date?
    @Published var localSteps: Int?

    private let healthKitManager = HealthKitManager.shared
    private let api = NexusAPI.shared
    private let coordinator = SyncCoordinator.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Sync State (derived from coordinator)

    var isLoading: Bool {
        timeseriesState == .loading || coordinator.domainStates[.dashboard]?.isSyncing == true
    }

    var healthTimeseries: [DailyHealthPoint] {
        timeseriesState.data
    }

    var hasTimeseriesData: Bool {
        timeseriesState.hasData
    }

    var timeseriesError: Bool {
        if case .failed = timeseriesState { return true }
        return false
    }

    var healthKitSyncError: Bool {
        coordinator.domainStates[.healthKit]?.lastError != nil
    }

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

    init() {
        subscribeToCoordinator()
    }

    // MARK: - Coordinator Subscription

    private func subscribeToCoordinator() {
        coordinator.$dashboardPayload
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                self?.dashboardPayload = payload
                self?.lastUpdated = Date()
                self?.dataSource = .network
            }
            .store(in: &cancellables)

        // Forward coordinator state changes so computed properties
        // (isLoading, healthKitSyncError) trigger view updates.
        coordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Loading

    func loadData() async {
        errorMessage = nil

        // Load local HealthKit data immediately (no server dependency)
        await fetchLocalHealthKit()

        // Load timeseries data (dashboard data comes from coordinator subscription)
        await loadHealthTimeseries(days: 30)

        // If coordinator hasn't provided data yet, use cached
        if dashboardPayload == nil {
            if let cached = DashboardService.shared.loadCached() {
                dashboardPayload = cached.payload
                lastUpdated = cached.lastUpdated
                dataSource = .cache
            }
        }

        // Check HealthKit status
        healthKitAuthorized = healthKitManager.isAuthorized
        let syncService = HealthKitSyncService.shared
        lastHealthKitSync = syncService.lastSyncDate
        healthKitSampleCount = syncService.lastSyncSampleCount
    }

    /// Fetch weight and steps directly from HealthKit for immediate display.
    func fetchLocalHealthKit() async {
        guard healthKitManager.isAuthorized else { return }

        if let (weight, date) = try? await healthKitManager.fetchLatestWeight() {
            localWeight = weight
            localWeightDate = date
        }

        if let steps = try? await healthKitManager.fetchTodaysSteps() {
            localSteps = steps
        }
    }

    func loadHealthTimeseries(days: Int = 30) async {
        timeseriesState = .loading
        do {
            let response = try await api.fetchHealthTimeseries(days: days)
            if response.success, let data = response.data {
                timeseriesState = .loaded(data)
            } else {
                timeseriesState = .failed("No timeseries data available")
            }
        } catch {
            timeseriesState = .failed(error.localizedDescription)
        }
    }

    func refreshHealthKit() async {
        coordinator.syncAll(force: true)
        // Brief wait for coordinator to process
        try? await Task.sleep(nanoseconds: 500_000_000)
        lastHealthKitSync = coordinator.domainStates[.healthKit]?.lastSuccessDate
            ?? HealthKitSyncService.shared.lastSyncDate
        healthKitSampleCount = HealthKitSyncService.shared.lastSyncSampleCount
    }

    // MARK: - Computed Insights

    func generateInsights() -> [HealthInsight] {
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
