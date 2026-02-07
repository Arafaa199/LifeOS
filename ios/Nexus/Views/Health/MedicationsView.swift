import SwiftUI
import os

struct MedicationsView: View {
    @StateObject private var coordinator = SyncCoordinator.shared
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "medications")

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
                                .foregroundColor(.nexusSuccess)
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

            // Doses Section
            if let doses = summary.medications, !doses.isEmpty {
                Section("Schedule") {
                    ForEach(doses) { dose in
                        MedicationDoseRow(dose: dose)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func adherenceColor(_ pct: Double) -> Color {
        if pct >= 90 { return .nexusSuccess }
        if pct >= 70 { return .orange }
        return .red
    }
}

// MARK: - Dose Row

struct MedicationDoseRow: View {
    let dose: MedicationDose

    var body: some View {
        HStack {
            // Status Icon
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundColor(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(dose.name)
                    .font(.body)

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
            return .nexusSuccess
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
