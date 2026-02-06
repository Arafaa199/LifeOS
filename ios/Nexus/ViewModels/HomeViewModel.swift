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

    // MARK: - Device Control

    func toggleDevice(_ entityId: String) async {
        do {
            let response = try await NexusAPI.shared.controlDevice(entityId: entityId, action: .toggle)
            if response.success {
                logger.info("[home] toggled \(entityId) → \(response.newState ?? "unknown")")
                // Refresh status to get updated state
                await fetchStatus()
            } else {
                errorMessage = response.error ?? "Failed to toggle device"
                logger.error("[home] toggle failed: \(response.error ?? "unknown")")
            }
        } catch {
            errorMessage = "Unable to control device"
            logger.error("[home] toggle error: \(error.localizedDescription)")
        }
    }

    func turnOn(_ entityId: String) async {
        await controlDevice(entityId, action: .turnOn)
    }

    func turnOff(_ entityId: String) async {
        await controlDevice(entityId, action: .turnOff)
    }

    func setLightBrightness(_ entityId: String, brightness: Int) async {
        do {
            let response = try await NexusAPI.shared.controlDevice(
                entityId: entityId,
                action: .turnOn,
                brightness: brightness
            )
            if response.success {
                logger.info("[home] set \(entityId) brightness to \(brightness)%")
                await fetchStatus()
            } else {
                errorMessage = response.error
            }
        } catch {
            errorMessage = "Unable to set brightness"
            logger.error("[home] brightness error: \(error.localizedDescription)")
        }
    }

    func vacuumCommand(_ command: HomeAction) async {
        guard let entityId = homeStatus?.vacuum?.entityId else { return }
        await controlDevice(entityId, action: command)
    }

    private func controlDevice(_ entityId: String, action: HomeAction) async {
        do {
            let response = try await NexusAPI.shared.controlDevice(entityId: entityId, action: action)
            if response.success {
                logger.info("[home] \(action.rawValue) \(entityId) → \(response.newState ?? "unknown")")
                await fetchStatus()
            } else {
                errorMessage = response.error ?? "Control failed"
            }
        } catch {
            errorMessage = "Unable to control device"
            logger.error("[home] control error: \(error.localizedDescription)")
        }
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
