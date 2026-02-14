import SwiftUI
import os

struct AddSupplementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Supplement) -> Void

    @State private var name = ""
    @State private var brand = ""
    @State private var doseAmount = ""
    @State private var doseUnit = "mg"
    @State private var frequency = DoseFrequency.daily
    @State private var selectedTimes: Set<TimeOfDay> = [.morning]
    @State private var category = SupplementCategory.supplement
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "supplements")

    private let doseUnits = ["mg", "mcg", "g", "IU", "ml", "capsule", "tablet", "drop"]

    var body: some View {
        NavigationView {
            Form {
                // Basic Info
                Section("Supplement Info") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    TextField("Brand (optional)", text: $brand)
                        .textInputAutocapitalization(.words)

                    Picker("Category", selection: $category) {
                        ForEach(SupplementCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                }

                // Dosage
                Section("Dosage") {
                    HStack {
                        TextField("Amount", text: $doseAmount)
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
                    Picker("Frequency", selection: $frequency) {
                        ForEach(DoseFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Times of day")
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
            .navigationTitle("Add Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || selectedTimes.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let request = SupplementCreateRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces),
            doseAmount: Double(doseAmount),
            doseUnit: doseAmount.isEmpty ? nil : doseUnit,
            frequency: frequency.rawValue,
            timesOfDay: selectedTimes.map { $0.rawValue },
            category: category.rawValue,
            notes: notes.isEmpty ? nil : notes
        )

        do {
            let response = try await NexusAPI.shared.createSupplement(request)
            logger.info("Created supplement: \(response.supplement.name)")
            onSave(response.supplement)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to create supplement: \(error.localizedDescription)")
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

// MARK: - Preview

#Preview {
    AddSupplementSheet { _ in }
}
