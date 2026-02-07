import SwiftUI
import os

struct AddWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Workout) -> Void

    @State private var workoutType = WorkoutType.strength
    @State private var name = ""
    @State private var durationHours = 0
    @State private var durationMinutes = 30
    @State private var calories = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "workouts")

    var body: some View {
        NavigationView {
            Form {
                // Workout Type
                Section("Workout Type") {
                    Picker("Type", selection: $workoutType) {
                        ForEach(WorkoutType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    TextField("Name (optional)", text: $name)
                }

                // Duration
                Section("Duration") {
                    HStack {
                        Picker("Hours", selection: $durationHours) {
                            ForEach(0..<6) { h in
                                Text("\(h) hr").tag(h)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100)

                        Picker("Minutes", selection: $durationMinutes) {
                            ForEach(0..<60) { m in
                                Text("\(m) min").tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100)
                    }
                    .frame(height: 120)
                }

                // Calories
                Section("Calories Burned (optional)") {
                    TextField("Calories", text: $calories)
                        .keyboardType(.numberPad)
                }

                // Notes
                Section("Notes (optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(totalMinutes == 0 || isSaving)
                }
            }
        }
    }

    private var totalMinutes: Int {
        durationHours * 60 + durationMinutes
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let request = WorkoutLogRequest(
            date: nil,
            workoutType: workoutType.rawValue,
            name: name.isEmpty ? nil : name,
            durationMin: totalMinutes,
            caloriesBurned: Int(calories),
            avgHr: nil,
            maxHr: nil,
            strain: nil,
            exercises: nil,
            distanceKm: nil,
            notes: notes.isEmpty ? nil : notes,
            source: "manual",
            startedAt: nil,
            endedAt: nil,
            externalId: nil
        )

        do {
            let response = try await NexusAPI.shared.logWorkout(request)
            if response.success, let workout = response.data?.workout {
                logger.info("Logged workout: \(workoutType.rawValue)")
                onSave(workout)
                dismiss()
            } else {
                errorMessage = response.message ?? "Failed to log workout"
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to log workout: \(error.localizedDescription)")
        }

        isSaving = false
    }
}

#Preview {
    AddWorkoutSheet { _ in }
}
