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
            ScrollView {
                VStack(spacing: 24) {
                    // Voice/Text Input Section
                    inputSection

                    // Quick Actions Grid
                    quickActionsSection

                    Spacer(minLength: 20)

                    // Submit Button
                    submitButton
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Quick Log")
            .navigationBarTitleDisplayMode(.large)
            .alert("Logged", isPresented: $showSuccess) {
                Button("OK", role: .cancel) {
                    inputText = ""
                }
            } message: {
                Text(resultMessage)
            }
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What did you do?")
                    .font(.headline)

                Spacer()

                // Voice input button
                Button(action: toggleVoiceInput) {
                    ZStack {
                        Circle()
                            .fill(speechRecognizer.isRecording ? Color.nexusError.opacity(0.15) : Color.nexusPrimary.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(speechRecognizer.isRecording ? .nexusError : .nexusPrimary)
                            .symbolEffect(.pulse, isActive: speechRecognizer.isRecording)
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: speechRecognizer.isRecording ? $speechRecognizer.transcript : $inputText)
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(speechRecognizer.isRecording ? Color.nexusError : Color.nexusPrimary.opacity(0.3), lineWidth: speechRecognizer.isRecording ? 2 : 1)
                    )
                    .focused($isInputFocused)
                    .disabled(speechRecognizer.isRecording)

                if inputText.isEmpty && !speechRecognizer.isRecording {
                    Text("Type or use voice...")
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }

                if speechRecognizer.isRecording {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.title2)
                                .foregroundColor(.nexusError)
                                .symbolEffect(.variableColor.iterative, isActive: true)
                            Text("Listening...")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.nexusError)
                        }
                        .padding(12)
                    }
                }
            }

            Text("Examples: \"2 eggs for breakfast\", \"500ml water\", \"weight 75kg\"")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .nexusCard()
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink(destination: FoodLogView(viewModel: viewModel)) {
                    NexusQuickActionCard(
                        title: "Log Food",
                        icon: "fork.knife",
                        color: .nexusFood
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: WaterLogView()) {
                    NexusQuickActionCard(
                        title: "Water",
                        icon: "drop.fill",
                        color: .nexusWater
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NexusQuickActionButton(
                    title: "Coffee",
                    icon: "cup.and.saucer.fill",
                    color: .brown
                ) {
                    logQuick("coffee with milk")
                }

                NexusQuickActionButton(
                    title: "Snack",
                    icon: "leaf.fill",
                    color: .nexusWeight
                ) {
                    logQuick("had a snack")
                }

                NexusQuickActionButton(
                    title: "Weight",
                    icon: "scalemass.fill",
                    color: .nexusFood
                ) {
                    isInputFocused = true
                    inputText = "weight "
                }
            }
        }
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button(action: submitLog) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.semibold))
                }
                Text(isLoading ? "Logging..." : "Log It")
                    .fontWeight(.semibold)
            }
        }
        .nexusPrimaryButton(disabled: inputText.isEmpty || isLoading)
        .disabled(inputText.isEmpty || isLoading)
    }

    // MARK: - Actions

    private func submitLog() {
        guard !inputText.isEmpty else { return }

        haptics.impactOccurred()
        isInputFocused = false
        isLoading = true

        Task {
            do {
                let response = try await api.logUniversalOffline(inputText)
                await MainActor.run {
                    isLoading = false
                    successHaptics.notificationOccurred(.success)
                    viewModel.updateSummaryAfterLog(type: .note, response: response)
                    resultMessage = response.message ?? "Logged successfully"
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
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
            haptics.impactOccurred()
            speechRecognizer.stopRecording()

            if !inputText.isEmpty {
                submitLog()
            }
        } else {
            haptics.impactOccurred()
            inputText = ""

            speechRecognizer.requestAuthorization { authorized in
                if authorized {
                    speechRecognizer.startRecording { result in
                        switch result {
                        case .success(let transcript):
                            if !transcript.isEmpty {
                                inputText = transcript
                            }
                        case .failure(let error):
                            successHaptics.notificationOccurred(.error)
                            resultMessage = "Speech error: \(error.localizedDescription)"
                            showSuccess = true
                        }
                    }
                } else {
                    successHaptics.notificationOccurred(.error)
                    resultMessage = "Speech recognition not authorized"
                    showSuccess = true
                }
            }
        }
    }
}

// Keep QuickActionButton for backwards compatibility
struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        NexusQuickActionButton(title: title, icon: icon, color: color, action: action)
    }
}

#Preview {
    QuickLogView(viewModel: DashboardViewModel())
}
