import SwiftUI
import os

struct SupplementDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let supplement: Supplement
    let onUpdate: () -> Void

    @State private var isEditing = false
    @State private var isDeactivating = false
    @State private var showingDeactivateConfirm = false

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "supplements")

    var body: some View {
        NavigationView {
            List {
                // Basic Info
                Section {
                    LabeledContent("Name", value: supplement.name)

                    if let brand = supplement.brand {
                        LabeledContent("Brand", value: brand)
                    }

                    LabeledContent("Category") {
                        HStack {
                            Image(systemName: supplement.categoryIcon)
                            Text(supplement.category.capitalized)
                        }
                    }
                }

                // Dosage
                Section("Dosage") {
                    if !supplement.displayDose.isEmpty {
                        LabeledContent("Amount", value: supplement.displayDose)
                    }
                    LabeledContent("Frequency", value: supplement.frequencyDisplay)

                    LabeledContent("Times") {
                        Text(supplement.timesOfDay.map { $0.capitalized }.joined(separator: ", "))
                    }
                }

                // Today's Status
                Section("Today") {
                    if let doses = supplement.todayDoses, !doses.isEmpty {
                        ForEach(doses, id: \.timeSlot) { dose in
                            HStack {
                                Image(systemName: TimeOfDay(rawValue: dose.timeSlot)?.icon ?? "clock")
                                    .foregroundColor(.secondary)

                                Text(dose.timeSlot.capitalized)

                                Spacer()

                                statusBadge(dose.status)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.orange)
                            Text("No doses logged today")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Notes
                if let notes = supplement.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .foregroundColor(.secondary)
                    }
                }

                // Actions
                Section {
                    Button(role: .destructive) {
                        showingDeactivateConfirm = true
                    } label: {
                        if isDeactivating {
                            HStack {
                                ProgressView()
                                    .tint(.red)
                                Text("Deactivating...")
                            }
                        } else {
                            Label("Deactivate Supplement", systemImage: "trash")
                        }
                    }
                    .disabled(isDeactivating)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Deactivate \(supplement.name)?",
                isPresented: $showingDeactivateConfirm,
                titleVisibility: .visible
            ) {
                Button("Deactivate", role: .destructive) {
                    deactivateSupplement()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will hide the supplement from your active list. You can reactivate it later.")
            }
        }
    }

    private func deactivateSupplement() {
        isDeactivating = true
        Task {
            do {
                _ = try await NexusAPI.shared.deactivateSupplement(id: supplement.id)
                logger.info("Deactivated supplement: \(supplement.name)")
                await MainActor.run {
                    onUpdate()
                    dismiss()
                }
            } catch {
                logger.error("Failed to deactivate supplement: \(error.localizedDescription)")
                isDeactivating = false
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon(status))
            Text(status.capitalized)
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(statusColor(status))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor(status).opacity(0.15))
        .cornerRadius(6)
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "taken": return "checkmark.circle.fill"
        case "skipped": return "xmark.circle.fill"
        default: return "clock"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "taken": return NexusTheme.Colors.Semantic.green
        case "skipped": return .red
        default: return .orange
        }
    }
}

// MARK: - Preview

#Preview {
    let sample = Supplement(
        id: 1,
        name: "Vitamin D3",
        brand: "NOW Foods",
        doseAmount: 5000,
        doseUnit: "IU",
        frequency: "daily",
        timesOfDay: ["morning"],
        category: "vitamin",
        notes: "Take with fatty meal for better absorption",
        active: true,
        startDate: "2024-01-01",
        endDate: nil,
        todayDoses: [SupplementDoseStatus(timeSlot: "morning", status: "taken")]
    )
    return SupplementDetailSheet(supplement: sample) {}
}
