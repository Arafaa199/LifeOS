import Foundation
import SwiftUI
import Combine
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "habits")

@MainActor
class HabitsViewModel: ObservableObject {
    @Published var habits: [Habit] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = HabitsAPI.shared

    // MARK: - Load

    func loadHabits() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.fetchHabits()
            habits = response.habits
        } catch {
            logger.error("Failed to load habits: \(error.localizedDescription)")
            errorMessage = "Failed to load habits"
        }

        isLoading = false
    }

    // MARK: - Complete (Optimistic UI)

    func completeHabit(id: Int) async {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        let original = habits[index]

        // Optimistic toggle
        habits[index] = original.toggled

        do {
            let request = LogHabitRequest(
                habitId: id,
                count: original.completedToday ? 0 : original.targetCount,
                notes: nil
            )
            let response = try await api.completeHabit(request)
            // Replace with server state
            if let idx = habits.firstIndex(where: { $0.id == id }) {
                habits[idx] = response.habit
            }
        } catch {
            logger.error("Failed to complete habit \(id): \(error.localizedDescription)")
            // Rollback
            if let idx = habits.firstIndex(where: { $0.id == id }) {
                habits[idx] = original
            }
            errorMessage = "Failed to update habit"
        }
    }

    // MARK: - Create

    func createHabit(_ request: CreateHabitRequest) async -> Bool {
        do {
            let response = try await api.createHabit(request)
            habits.append(response.habit)
            return true
        } catch {
            logger.error("Failed to create habit: \(error.localizedDescription)")
            errorMessage = "Failed to create habit"
            return false
        }
    }

    // MARK: - Delete (Soft)

    func deleteHabit(id: Int) async {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        let original = habits[index]

        // Optimistic remove
        habits.remove(at: index)

        do {
            let response = try await api.deleteHabit(id: id)
            if !response.success {
                logger.warning("Server rejected delete for habit \(id)")
                habits.insert(original, at: min(index, habits.count))
                errorMessage = "Failed to delete habit"
            }
        } catch {
            logger.error("Failed to delete habit \(id): \(error.localizedDescription)")
            // Rollback
            habits.insert(original, at: min(index, habits.count))
            errorMessage = "Failed to delete habit"
        }
    }

    // MARK: - Computed

    var completedCount: Int {
        habits.filter(\.completedToday).count
    }

    var totalCount: Int {
        habits.count
    }

    var completionProgress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var groupedHabits: [(category: String, habits: [Habit])] {
        let grouped = Dictionary(grouping: habits) { $0.category ?? "other" }
        let order = ["health", "fitness", "productivity", "mindfulness", "other"]
        return order.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (category: cat, habits: items)
        }
    }

    var streakLeader: Habit? {
        habits.filter { $0.currentStreak > 0 }
            .max(by: { $0.currentStreak < $1.currentStreak })
    }

    var incompleteHabits: [Habit] {
        habits.filter { !$0.completedToday }
    }
}
