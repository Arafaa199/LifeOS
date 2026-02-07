import SwiftUI
import os

struct MoodLogView: View {
    @State private var moodScore: Int = 5
    @State private var energyScore: Int = 5
    @State private var notes: String = ""
    @State private var isLogging = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "mood")

    private let moodEmojis = ["😫", "😢", "😔", "😐", "🙂", "😊", "😄", "😁", "🤩", "🥳"]
    private let energyEmojis = ["🪫", "😴", "🥱", "😑", "😐", "🙂", "😀", "💪", "⚡️", "🔥"]

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                moodSection
                energySection
                notesSection
                logButton
            }
            .padding()
        }
        .background(Color.nexusBackground)
        .navigationTitle("Log Mood")
        .navigationBarTitleDisplayMode(.large)
        .alert("Logged!", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Mood: \(moodScore)/10, Energy: \(energyScore)/10")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    // MARK: - Mood Section

    private var moodSection: some View {
        VStack(spacing: 16) {
            Text("How are you feeling?")
                .font(.headline)

            Text(moodEmojis[moodScore - 1])
                .font(.system(size: 64))
                .animation(.easeInOut, value: moodScore)

            HStack {
                Text("1")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: Binding(
                    get: { Double(moodScore) },
                    set: { moodScore = Int($0) }
                ), in: 1...10, step: 1)
                .accentColor(.nexusPrimary)
                .accessibilityLabel("Mood score")
                .accessibilityValue("\(moodScore) out of 10")

                Text("10")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Mood: \(moodScore)/10")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Energy Section

    private var energySection: some View {
        VStack(spacing: 16) {
            Text("Energy level?")
                .font(.headline)

            Text(energyEmojis[energyScore - 1])
                .font(.system(size: 64))
                .animation(.easeInOut, value: energyScore)

            HStack {
                Text("1")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: Binding(
                    get: { Double(energyScore) },
                    set: { energyScore = Int($0) }
                ), in: 1...10, step: 1)
                .accentColor(.orange)
                .accessibilityLabel("Energy level")
                .accessibilityValue("\(energyScore) out of 10")

                Text("10")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Energy: \(energyScore)/10")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes (optional)")
                .font(.headline)

            TextField("What's on your mind?", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Log Button

    private var logButton: some View {
        Button {
            logMood()
        } label: {
            HStack {
                if isLogging {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "heart.fill")
                    Text("Log Mood")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.nexusPrimary)
            .cornerRadius(12)
        }
        .disabled(isLogging)
    }

    // MARK: - Actions

    private func logMood() {
        isLogging = true

        Task {
            do {
                let response = try await NexusAPI.shared.logMood(
                    mood: moodScore,
                    energy: energyScore,
                    notes: notes.isEmpty ? nil : notes
                )

                if response.success {
                    logger.info("Logged mood: \(moodScore), energy: \(energyScore)")
                    showSuccess = true
                } else {
                    errorMessage = response.message ?? "Failed to log mood"
                }
            } catch {
                logger.error("Failed to log mood: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }

            isLogging = false
        }
    }
}

#Preview {
    NavigationView {
        MoodLogView()
    }
}
