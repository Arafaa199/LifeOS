import Combine
import Foundation
import os

@MainActor
class BJJViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "bjj")
    private let api = HealthAPI.shared

    @Published var sessions: [BJJSession] = []
    @Published var streak: BJJStreakInfo?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?

    // Pagination
    @Published var currentPage = 0
    @Published var hasMore = true
    private let pageSize = 20

    // Logging state
    @Published var isLogging = false
    @Published var logError: String?

    // MARK: - Load Data

    func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        currentPage = 0
        hasMore = true

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadStreak() }
            group.addTask { await self.loadHistory(reset: true) }
        }

        isLoading = false
    }

    func loadStreak() async {
        do {
            let response = try await api.fetchBJJStreak()
            streak = response.streakInfo
            logger.info("Loaded BJJ streak: \(response.currentStreak) weeks")
        } catch {
            logger.error("Failed to load BJJ streak: \(error.localizedDescription)")
        }
    }

    func loadHistory(reset: Bool = false) async {
        if reset {
            currentPage = 0
            hasMore = true
        }

        guard hasMore else { return }

        do {
            let response = try await api.fetchBJJHistory(limit: pageSize, offset: currentPage * pageSize)

            if reset {
                sessions = response.sessions
            } else {
                sessions.append(contentsOf: response.sessions)
            }

            streak = response.streak
            hasMore = response.sessions.count >= pageSize
            currentPage += 1

            logger.info("Loaded \(response.sessions.count) BJJ sessions, total: \(self.sessions.count)")
        } catch {
            logger.error("Failed to load BJJ history: \(error.localizedDescription)")
            if sessions.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore() async {
        guard !isLoadingMore && hasMore else { return }
        isLoadingMore = true
        await loadHistory(reset: false)
        isLoadingMore = false
    }

    // MARK: - Log Session

    func logSession(_ request: LogBJJRequest) async -> Bool {
        isLogging = true
        logError = nil

        // Optimistic UI update
        let optimisticSession = BJJSession(
            id: -1,
            sessionDate: request.sessionDate,
            sessionType: request.sessionType,
            durationMinutes: request.durationMinutes,
            startTime: request.startTime,
            endTime: request.endTime,
            strain: request.strain,
            hrAvg: request.hrAvg,
            calories: request.calories,
            source: request.source,
            techniques: request.techniques,
            notes: request.notes,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        // Insert at top of list
        sessions.insert(optimisticSession, at: 0)

        // Update streak optimistically
        if var currentStreak = streak {
            currentStreak = BJJStreakInfo(
                currentStreak: currentStreak.currentStreak,
                longestStreak: currentStreak.longestStreak,
                totalSessions: currentStreak.totalSessions + 1,
                sessionsThisMonth: currentStreak.sessionsThisMonth + 1,
                sessionsThisWeek: currentStreak.sessionsThisWeek + 1
            )
            streak = currentStreak
        }

        do {
            let response = try await api.logBJJSession(request)

            // Replace optimistic session with real one
            if let index = sessions.firstIndex(where: { $0.id == -1 }) {
                sessions[index] = response.session
            }

            logger.info("BJJ session logged: \(response.session.sessionType) on \(response.session.sessionDate)")

            // Reload streak for accurate numbers
            await loadStreak()

            isLogging = false
            return true
        } catch {
            logger.error("Failed to log BJJ session: \(error.localizedDescription)")
            logError = error.localizedDescription

            // Revert optimistic update
            sessions.removeAll { $0.id == -1 }
            await loadStreak()

            isLogging = false
            return false
        }
    }

    // MARK: - Delete Session

    func deleteSession(id: Int) async -> Bool {
        do {
            let response = try await api.deleteBJJSession(id: id)
            if response.success {
                sessions.removeAll { $0.id == id }
                await loadStreak()
                logger.info("Deleted BJJ session id=\(id)")
                return true
            }
            logError = "Failed to delete session"
            return false
        } catch {
            logger.error("Failed to delete BJJ session: \(error.localizedDescription)")
            logError = error.localizedDescription
            return false
        }
    }

    // MARK: - Update Session

    func updateSession(_ request: BJJUpdateRequest) async -> Bool {
        do {
            let response = try await api.updateBJJSession(request)
            if response.success {
                if let index = sessions.firstIndex(where: { $0.id == request.id }) {
                    sessions[index] = response.session
                }
                await loadStreak()
                logger.info("Updated BJJ session id=\(request.id)")
                return true
            }
            logError = "Failed to update session"
            return false
        } catch {
            logger.error("Failed to update BJJ session: \(error.localizedDescription)")
            logError = error.localizedDescription
            return false
        }
    }

    // MARK: - Helpers

    func refresh() async {
        await loadInitialData()
    }
}
