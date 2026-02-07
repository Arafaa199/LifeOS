import SwiftUI
import Combine

/// Displays recurring subscriptions with next renewal dates and monthly total
struct SubscriptionsView: View {
    @StateObject private var viewModel = SubscriptionsViewModel()

    var body: some View {
        List {
            // Header with monthly total
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly Subscriptions")
                            .font(.headline)
                        Text("\(viewModel.subscriptions.count) active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatCurrency(viewModel.monthlyTotal, currency: "AED"))
                            .font(.title2.bold())
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                        Text("per month")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Due soon section
            if !viewModel.dueSoon.isEmpty {
                Section("Due Soon") {
                    ForEach(viewModel.dueSoon) { item in
                        SubscriptionRow(item: item, showDueDate: true)
                    }
                }
            }

            // All subscriptions
            Section("All Subscriptions") {
                if viewModel.subscriptions.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    ForEach(viewModel.subscriptions) { item in
                        SubscriptionRow(item: item, showDueDate: false)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load()
        }
        .overlay {
            if viewModel.isLoading && viewModel.subscriptions.isEmpty {
                ProgressView()
            }
        }
        .onAppear {
            Task { await viewModel.load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "repeat.circle")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No subscriptions found")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Add recurring items marked as monthly to see them here")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Subscription Row

struct SubscriptionRow: View {
    let item: RecurringItem
    let showDueDate: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: categoryIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(categoryColor)
            }

            // Name and cadence
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.cadenceDisplay)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if showDueDate, let dueDate = item.dueDateFormatted {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(dueDate)
                            .font(.caption)
                            .foregroundColor(item.isOverdue ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.Semantic.amber)
                    }
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(item.amount, currency: item.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(NexusTheme.Colors.Semantic.red)

                if !showDueDate, let days = item.daysUntilDue, days >= 0 {
                    Text(daysUntilText(days))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var categoryIcon: String {
        let name = item.name.lowercased()
        if name.contains("netflix") || name.contains("disney") || name.contains("hbo") || name.contains("youtube") {
            return "play.tv.fill"
        } else if name.contains("spotify") || name.contains("apple music") || name.contains("anghami") {
            return "music.note"
        } else if name.contains("gym") || name.contains("fitness") {
            return "figure.run"
        } else if name.contains("cloud") || name.contains("icloud") || name.contains("storage") {
            return "cloud.fill"
        } else if name.contains("phone") || name.contains("etisalat") || name.contains("du ") {
            return "phone.fill"
        } else if name.contains("internet") || name.contains("wifi") {
            return "wifi"
        } else {
            return "repeat.circle.fill"
        }
    }

    private var categoryColor: Color {
        let name = item.name.lowercased()
        if name.contains("netflix") || name.contains("disney") || name.contains("hbo") || name.contains("youtube") {
            return .red
        } else if name.contains("spotify") || name.contains("apple music") {
            return .green
        } else if name.contains("gym") || name.contains("fitness") {
            return .orange
        } else {
            return NexusTheme.Colors.Semantic.green
        }
    }

    private func daysUntilText(_ days: Int) -> String {
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days)d"
    }
}

// MARK: - View Model

@MainActor
class SubscriptionsViewModel: ObservableObject {
    @Published var subscriptions: [RecurringItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = NexusAPI.shared

    /// Monthly subscription categories (patterns to match)
    private let subscriptionPatterns = [
        "subscription", "netflix", "spotify", "disney", "hbo", "youtube",
        "apple music", "anghami", "gym", "fitness", "icloud", "cloud",
        "adobe", "microsoft", "office", "etisalat", "du ", "internet"
    ]

    var monthlyTotal: Double {
        subscriptions.reduce(0) { $0 + $1.monthlyEquivalent }
    }

    var dueSoon: [RecurringItem] {
        subscriptions.filter { $0.isDueSoon || $0.isOverdue }
            .sorted { ($0.daysUntilDue ?? 999) < ($1.daysUntilDue ?? 999) }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await api.fetchRecurringItems()
            if response.success, let data = response.data {
                // Filter: active, expense, monthly cadence OR subscription-like name
                subscriptions = data.filter { item in
                    guard item.isActive && item.isExpense else { return false }
                    // Include monthly items
                    if item.cadence == "monthly" { return true }
                    // Include items with subscription-like names
                    let nameLower = item.name.lowercased()
                    return subscriptionPatterns.contains { nameLower.contains($0) }
                }
                .sorted { $0.name < $1.name }
            }
        } catch {
            errorMessage = "Failed to load subscriptions: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationView {
        SubscriptionsView()
    }
}
