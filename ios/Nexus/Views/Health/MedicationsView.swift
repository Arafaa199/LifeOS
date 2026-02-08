import SwiftUI
import os

struct MedicationsView: View {
    @StateObject private var coordinator = SyncCoordinator.shared
    @State private var showingAddMedication = false
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "medications")
    private let api = NexusAPI.shared

    private var medications: MedicationsSummary? {
        coordinator.dashboardPayload?.medicationsToday
    }

    var body: some View {
        Group {
            if let meds = medications {
                medicationsList(meds)
            } else {
                ContentUnavailableView(
                    "No Medication Data",
                    systemImage: "pills",
                    description: Text("Medication tracking requires iOS 18+ and HealthKit permissions")
                )
            }
        }
        .navigationTitle("Medications")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingAddMedication = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add medication")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Double tap to add a new medication")
            }
        }
        .sheet(isPresented: $showingAddMedication) {
            AddMedicationSheet(onSave: { Task { await refresh() } })
        }
        .refreshable {
            await coordinator.sync(.dashboard)
        }
    }

    // MARK: - Medications List

    private func medicationsList(_ summary: MedicationsSummary) -> some View {
        List {
            // Summary Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's Progress")
                            .font(.headline)

                        HStack(spacing: 4) {
                            Text("\(summary.takenToday)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(NexusTheme.Colors.Semantic.green)
                            Text("of \(summary.dueToday) taken")
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if let adherence = summary.adherencePct {
                        VStack(alignment: .trailing) {
                            Text("\(Int(adherence))%")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(adherenceColor(adherence))
                            Text("Adherence")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)

                if summary.skippedToday > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("\(summary.skippedToday) skipped today")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                }
            }

            // Doses Section (interactive — tap to cycle status)
            if let doses = summary.medications, !doses.isEmpty {
                Section("Schedule") {
                    ForEach(doses) { dose in
                        MedicationDoseRow(dose: dose) {
                            Task { await toggleDose(dose) }
                        }
                    }
                }

                Section {
                    Text("Tap a dose to cycle: Pending → Taken → Skipped")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func toggleDose(_ dose: MedicationDose) async {
        let nextStatus: String
        switch dose.status {
        case "pending", "scheduled": nextStatus = "taken"
        case "taken": nextStatus = "skipped"
        case "skipped": nextStatus = "scheduled"
        default: nextStatus = "taken"
        }

        let todayStr: String = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.locale = Locale(identifier: "en_US_POSIX")
            return fmt.string(from: Date())
        }()

        do {
            let _: NexusResponse = try await api.post(
                "/webhook/nexus-medication-toggle",
                body: MedicationToggleRequest(
                    medication_id: dose.name,
                    scheduled_date: todayStr,
                    scheduled_time: dose.scheduledTime,
                    new_status: nextStatus
                )
            )
            NexusTheme.Haptics.success()
            // Refresh dashboard to update medications summary
            await coordinator.sync(.dashboard)
        } catch {
            NexusTheme.Haptics.error()
            logger.error("Failed to toggle dose: \(error.localizedDescription)")
        }
    }

    private func adherenceColor(_ pct: Double) -> Color {
        if pct >= 90 { return NexusTheme.Colors.Semantic.green }
        if pct >= 70 { return .orange }
        return .red
    }

    private func refresh() async {
        await coordinator.sync(.dashboard)
    }
}

// MARK: - Dose Row (now accepts an onTap action)

struct MedicationDoseRow: View {
    let dose: MedicationDose
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack {
                // Status Icon
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundColor(statusColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dose.name)
                        .font(.body)
                        .foregroundColor(.primary)

                    if let time = dose.scheduledTime {
                        Text(time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(statusColor)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dose.name)\(dose.scheduledTime.map { ", scheduled at \($0)" } ?? ""), status: \(statusText)")
        .accessibilityHint("Double tap to cycle through: Pending, Taken, Skipped")
        .accessibilityAddTraits(.isButton)
    }

    private var statusIcon: String {
        switch dose.status {
        case "taken":
            return "checkmark.circle.fill"
        case "skipped":
            return "xmark.circle.fill"
        case "pending":
            return "clock.fill"
        default:
            return "circle"
        }
    }

    private var statusColor: Color {
        switch dose.status {
        case "taken":
            return NexusTheme.Colors.Semantic.green
        case "skipped":
            return .red
        case "pending":
            return .orange
        default:
            return .secondary
        }
    }

    private var statusText: String {
        switch dose.status {
        case "taken":
            return "Taken"
        case "skipped":
            return "Skipped"
        case "pending":
            return "Pending"
        default:
            return dose.status
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        MedicationsView()
    }
}
