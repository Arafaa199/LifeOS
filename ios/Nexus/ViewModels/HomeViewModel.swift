import SwiftUI
import Combine
import os

/// Home Assistant status view model with device control support.
@MainActor
class HomeViewModel: ObservableObject {
    static let shared = HomeViewModel()

    @Published var homeStatus: HomeStatus?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var controllingDevice: String?

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "home")
    private let hapticManager = UIImpactFeedbackGenerator(style: .light)

    private init() {}

    // MARK: - Fetch Status (Read-Only)

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
                logger.info("[home] status fetched")
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

    // MARK: - Computed Properties

    var hasData: Bool {
        homeStatus != nil
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

    // MARK: - Device Control

    func controlDevice(entityId: String, action: HomeAction) async {
        controllingDevice = entityId
        errorMessage = nil

        do {
            let response = try await NexusAPI.shared.controlDevice(
                entityId: entityId,
                action: action
            )

            if response.success {
                hapticManager.impactOccurred()
                logger.info("[home] device controlled: \(entityId) -> \(action.rawValue)")

                // Refresh status after successful control
                await fetchStatus()
            } else {
                hapticManager.impactOccurred()
                errorMessage = response.error ?? "Failed to control device"
                logger.error("[home] control failed: \(response.error ?? "unknown")")
            }
        } catch {
            hapticManager.impactOccurred()
            errorMessage = "Unable to control device"
            logger.error("[home] control error: \(error.localizedDescription)")
        }

        controllingDevice = nil
    }

    // MARK: - Open Home Assistant

    /// Opens the Home Assistant Companion app if installed, otherwise falls back to web dashboard
    func openHomeAssistant() {
        // Try HA Companion app first
        if let haAppURL = URL(string: "homeassistant://navigate/lovelace/0"),
           UIApplication.shared.canOpenURL(haAppURL) {
            UIApplication.shared.open(haAppURL)
            return
        }

        // Fallback to web dashboard
        if let webURL = URL(string: "https://ha.rfanw") {
            UIApplication.shared.open(webURL)
        }
    }
}
