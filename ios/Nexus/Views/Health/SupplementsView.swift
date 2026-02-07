import SwiftUI
import os

struct SupplementsView: View {
    @State private var supplements: [Supplement] = []
    @State private var summary: SupplementsSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddSheet = false
    @State private var selectedSupplement: Supplement?

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "supplements")

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading supplements...")
            } else if let error = errorMessage {
                errorView(error)
            } else if supplements.isEmpty {
                emptyStateView
            } else {
                supplementsList
            }
        }
        .navigationTitle("Supplements")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSupplementSheet { newSupplement in
                supplements.insert(newSupplement, at: 0)
            }
        }
        .sheet(item: $selectedSupplement) { supplement in
            SupplementDetailSheet(supplement: supplement) {
                Task { await loadSupplements() }
            }
        }
        .refreshable {
            await loadSupplements()
        }
        .task {
            await loadSupplements()
        }
    }

    // MARK: - Supplements List

    private var supplementsList: some View {
        List {
            // Summary Section
            if let summary = summary {
                Section {
                    summaryCard(summary)
                }
            }

            // Today's Doses
            Section("Today") {
                ForEach(supplements) { supplement in
                    SupplementRow(
                        supplement: supplement,
                        onTake: { await logDose(supplement, status: "taken") },
                        onSkip: { await logDose(supplement, status: "skipped") },
                        onTap: { selectedSupplement = supplement }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Summary Card

    private func summaryCard(_ summary: SupplementsSummary) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Progress")
                        .font(.headline)

                    HStack(spacing: 4) {
                        Text("\(summary.taken)")
                            .font(.title2.bold())
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                        Text("of \(summary.totalDosesToday) taken")
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let adherence = summary.adherencePct {
                    CircularProgressView(
                        progress: Double(adherence) / 100,
                        lineWidth: 6,
                        size: 60,
                        color: adherenceColor(adherence)
                    ) {
                        Text("\(adherence)%")
                            .font(.caption.bold())
                    }
                }
            }

            if summary.pending > 0 {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                    Text("\(summary.pending) doses remaining today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Supplements", systemImage: "pills.fill")
        } description: {
            Text("Add your daily supplements and medications to track adherence.")
        } actions: {
            Button("Add Supplement") {
                showAddSheet = true
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry") {
                Task { await loadSupplements() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func adherenceColor(_ pct: Int) -> Color {
        if pct >= 90 { return NexusTheme.Colors.Semantic.green }
        if pct >= 70 { return .orange }
        return .red
    }

    // MARK: - API

    private func loadSupplements() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await NexusAPI.shared.fetchSupplements()
            supplements = response.supplements
            summary = response.summary
            logger.info("Loaded \(response.supplements.count) supplements")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to load supplements: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func logDose(_ supplement: Supplement, status: String) async {
        let request = SupplementLogRequest(
            supplementId: supplement.id,
            status: status,
            timeSlot: nil,
            notes: nil
        )

        do {
            _ = try await NexusAPI.shared.logSupplementDose(request)
            await loadSupplements()
            logger.info("Logged \(status) for \(supplement.name)")
        } catch {
            logger.error("Failed to log dose: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supplement Row

struct SupplementRow: View {
    let supplement: Supplement
    let onTake: () async -> Void
    let onSkip: () async -> Void
    let onTap: () -> Void

    @State private var isLogging = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status indicator
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundColor(statusColor)
                    .frame(width: 32)

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(supplement.name)
                        .font(.body)
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        if !supplement.displayDose.isEmpty {
                            Text(supplement.displayDose)
                        }
                        Text("•")
                        Text(supplement.frequencyDisplay)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                // Quick actions
                if supplement.todayStatus == "pending" {
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                isLogging = true
                                await onTake()
                                isLogging = false
                            }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(NexusTheme.Colors.Semantic.green)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task {
                                isLogging = true
                                await onSkip()
                                isLogging = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .opacity(isLogging ? 0.5 : 1)
                    .disabled(isLogging)
                } else {
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.15))
                        .cornerRadius(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var statusIcon: String {
        switch supplement.todayStatus {
        case "taken": return "checkmark.circle.fill"
        case "partial": return "circle.bottomhalf.filled"
        case "skipped": return "xmark.circle.fill"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch supplement.todayStatus {
        case "taken": return NexusTheme.Colors.Semantic.green
        case "partial": return .orange
        case "skipped": return .red
        default: return .secondary
        }
    }

    private var statusText: String {
        switch supplement.todayStatus {
        case "taken": return "Taken"
        case "partial": return "Partial"
        case "skipped": return "Skipped"
        default: return "Pending"
        }
    }
}

// MARK: - Circular Progress View

struct CircularProgressView<Content: View>: View {
    let progress: Double
    let lineWidth: CGFloat
    let size: CGFloat
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)

            content
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        SupplementsView()
    }
}
