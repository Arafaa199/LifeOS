import Foundation
import Combine
import os

@MainActor
class HomeViewModel: ObservableObject {
    @Published var homeStatus: HomeStatus?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "home")
    private var refreshTimer: Timer?

    // MARK: - Fetch Status

    func fetchStatus() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await NexusAPI.shared.fetchHomeStatus()
            if response.success, let home = response.home {
                homeStatus = home
                if let updatedStr = response.lastUpdated {
                    lastUpdated = ISO8601DateFormatter().date(from: updatedStr)
                }
                logger.info("[home] status fetched successfully")
            } else {
                errorMessage = response.error ?? "Failed to fetch home status"
                logger.error("[home] fetch failed: \(response.error ?? "unknown")")
            }
        } catch {
            errorMessage = "Unable to connect to home"
            logger.error("[home] fetch error: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Auto-Refresh

    func startAutoRefresh(interval: TimeInterval = 30) {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchStatus()
            }
        }
        logger.debug("[home] auto-refresh started (\(Int(interval))s)")
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Computed Properties

    var hasData: Bool {
        homeStatus != nil
    }

    var vacuumBatteryColor: String {
        guard let battery = homeStatus?.vacuum?.battery else { return "gray" }
        if battery > 50 { return "green" }
        if battery > 20 { return "yellow" }
        return "red"
    }

    var summaryText: String {
        guard let status = homeStatus else { return "Loading..." }

        var parts: [String] = []

        if status.lightsOn {
            parts.append("Lights on")
        }
        if status.monitorsOn {
            parts.append("Monitors on")
        }
        if let vacuum = status.vacuum, vacuum.isCleaning {
            parts.append("Vacuum cleaning")
        }

        if parts.isEmpty {
            return "All quiet"
        }
        return parts.joined(separator: " · ")
    }
}
