import SwiftUI

struct QuickLogView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var resultMessage = ""
    @FocusState private var isInputFocused: Bool

    @StateObject private var speechRecognizer = SpeechRecognizer()
    private let api = NexusAPI.shared
    private let haptics = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptics = UINotificationFeedbackGenerator()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Voice/Text Input Area
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("What did you do?")
                            .font(.headline)

                        Spacer()

                        Button(action: toggleVoiceInput) {
                            Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                                .foregroundColor(speechRecognizer.isRecording ? .red : .blue)
                                .font(.title3)
                                .symbolEffect(.pulse, isActive: speechRecognizer.isRecording)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: speechRecognizer.isRecording ? $speechRecognizer.transcript : $inputText)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .focused($isInputFocused)
                            .disabled(speechRecognizer.isRecording)

                        if speechRecognizer.isRecording {
                            // Recording indicator
                            HStack {
                                Spacer()
                                VStack {
                                    Image(systemName: "waveform")
                                        .foregroundColor(.red)
                                        .symbolEffect(.variableColor.iterative, isActive: true)
                                    Text("Listening...")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                                .padding(8)
                            }
                        }
                    }

                    if !speechRecognizer.isRecording {
                        Text("Examples: \"2 eggs for breakfast\", \"500ml water\", \"weight 75kg\", \"mood 7, energy 6\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Speak now, tap mic again when done to auto-submit")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()

                // Quick Actions
                VStack(spacing: 12) {
                    Text("Quick Actions")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        QuickActionButton(
                            title: "Water",
                            icon: "drop.fill",
                            color: .blue
                        ) {
                            logQuick("1 glass of water")
                        }

                        QuickActionButton(
                            title: "Coffee",
                            icon: "cup.and.saucer.fill",
                            color: .brown
                        ) {
                            logQuick("coffee with milk")
                        }

                        QuickActionButton(
                            title: "Snack",
                            icon: "leaf.fill",
                            color: .green
                        ) {
                            logQuick("had a snack")
                        }

                        QuickActionButton(
                            title: "Weight",
                            icon: "scalemass.fill",
                            color: .orange
                        ) {
                            // Would open a number picker
                            isInputFocused = true
                            inputText = "weight "
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Submit Button
                Button(action: submitLog) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isLoading ? "Logging..." : "Log It")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(inputText.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(inputText.isEmpty || isLoading)
                .padding()
            }
            .navigationTitle("Quick Log")
            .alert("Success", isPresented: $showSuccess) {
                Button("OK", role: .cancel) {
                    inputText = ""
                }
            } message: {
                Text(resultMessage)
            }
        }
    }

    private func submitLog() {
        guard !inputText.isEmpty else { return }

        // Haptic feedback on tap
        haptics.impactOccurred()

        // Dismiss keyboard
        isInputFocused = false

        isLoading = true

        Task {
            do {
                // Use offline-capable API for reliability
                let response = try await api.logUniversalOffline(inputText)
                await MainActor.run {
                    isLoading = false
                    // Success haptic (even if queued offline)
                    successHaptics.notificationOccurred(.success)

                    // Update dashboard
                    viewModel.updateSummaryAfterLog(type: .note, response: response)

                    resultMessage = response.message ?? "Logged successfully"
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false

                    // Error haptic
                    successHaptics.notificationOccurred(.error)

                    resultMessage = error.localizedDescription
                    showSuccess = true
                }
            }
        }
    }

    private func logQuick(_ text: String) {
        inputText = text
        submitLog()
    }

    private func toggleVoiceInput() {
        if speechRecognizer.isRecording {
            // Stop recording
            haptics.impactOccurred()
            speechRecognizer.stopRecording()

            // Auto-submit if there's content
            if !inputText.isEmpty {
                submitLog()
            }
        } else {
            // Start recording
            haptics.impactOccurred()
            inputText = "" // Clear previous input

            speechRecognizer.requestAuthorization { authorized in
                if authorized {
                    speechRecognizer.startRecording { result in
                        switch result {
                        case .success(let transcript):
                            // Final transcript
                            if !transcript.isEmpty {
                                inputText = transcript
                            }
                        case .failure(let error):
                            successHaptics.notificationOccurred(.error)
                            resultMessage = "Speech recognition error: \(error.localizedDescription)"
                            showSuccess = true
                        }
                    }
                } else {
                    successHaptics.notificationOccurred(.error)
                    resultMessage = "Speech recognition not authorized. Please enable in Settings."
                    showSuccess = true
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .bold()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    QuickLogView(viewModel: DashboardViewModel())
}
