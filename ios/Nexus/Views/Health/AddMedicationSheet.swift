import SwiftUI
import os

struct AddMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void

    @State private var medicationName = ""
    @State private var brand = ""
    @State private var doseAmount = ""
    @State private var doseUnit = "mg"
    @State private var frequency = DoseFrequency.daily
    @State private var selectedTimes: Set<TimeOfDay> = [.morning]
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "medications")

    private let doseUnits = ["mg", "ml", "mcg", "IU", "tablet", "capsule", "drops"]

    var body: some View {
        NavigationView {
            Form {
                // Medication Info
                Section("Medication Info") {
                    TextField("Medication Name *", text: $medicationName)
                        .textInputAutocapitalization(.words)

                    TextField("Brand (optional)", text: $brand)
                        .textInputAutocapitalization(.words)
                }

                // Dosage
                Section("Dosage") {
                    HStack {
                        TextField("Amount (optional)", text: $doseAmount)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)

                        Picker("Unit", selection: $doseUnit) {
                            ForEach(doseUnits, id: \.self) { unit in
                                Text(unit).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                // Schedule
                Section("Schedule") {
                    Picker("Frequency *", selection: $frequency) {
                        ForEach(DoseFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Times of day *")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        FlowLayout(spacing: 8) {
                            ForEach(TimeOfDay.allCases, id: \.self) { time in
                                TimeChip(
                                    time: time,
                                    isSelected: selectedTimes.contains(time)
                                ) {
                                    if selectedTimes.contains(time) {
                                        selectedTimes.remove(time)
                                    } else {
                                        selectedTimes.insert(time)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Notes
                Section("Notes (optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(NexusTheme.Colors.Semantic.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(medicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTimes.isEmpty || isSaving || (Double(doseAmount) ?? 0) <= 0 && !doseAmount.isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let request = MedicationCreateRequest(
            medication_name: medicationName.trimmingCharacters(in: .whitespaces),
            brand: brand.isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces),
            dose_quantity: Double(doseAmount),
            dose_unit: doseAmount.isEmpty ? nil : doseUnit,
            frequency: frequency.rawValue,
            times_of_day: selectedTimes.map { $0.rawValue },
            notes: notes.isEmpty ? nil : notes
        )

        do {
            let response = try await NexusAPI.shared.createMedication(request)
            logger.info("Created medication: \(medicationName)")
            NexusTheme.Haptics.success()
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to create medication: \(error.localizedDescription)")
            NexusTheme.Haptics.error()
        }

        isSaving = false
    }
}

// MARK: - Time Chip

private struct TimeChip: View {
    let time: TimeOfDay
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: time.icon)
                    .font(.caption)
                Text(time.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? NexusTheme.Colors.accent : Color.secondary.opacity(0.15))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

// MARK: - Preview

#Preview {
    AddMedicationSheet { }
}
