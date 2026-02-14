import SwiftUI

struct QuickLogView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var resultMessage = ""
    @FocusState private var isInputFocused: Bool

    @StateObject private var speechRecognizer = SpeechRecognizer()
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
            .background(NexusTheme.Colors.background)
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
                            .fill(speechRecognizer.isRecording ? NexusTheme.Colors.Semantic.red.opacity(0.15) : NexusTheme.Colors.accent.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(speechRecognizer.isRecording ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.accent)
                            .symbolEffect(.pulse, isActive: speechRecognizer.isRecording)
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: speechRecognizer.isRecording ? $speechRecognizer.transcript : $inputText)
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(NexusTheme.Colors.card)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(speechRecognizer.isRecording ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.accent.opacity(0.3), lineWidth: speechRecognizer.isRecording ? 2 : 1)
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
                                .foregroundColor(NexusTheme.Colors.Semantic.red)
                                .symbolEffect(.variableColor.iterative, isActive: true)
                            Text("Listening...")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(NexusTheme.Colors.Semantic.red)
                        }
                        .padding(12)
                    }
                }
            }

            Text("Examples: \"2 eggs for breakfast\", \"500ml water\", \"weight 75kg\"")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .themeCard()
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink(destination: FoodLogView(viewModel: viewModel)) {
                    quickActionLabel("Log Food", icon: "fork.knife", color: NexusTheme.Colors.Semantic.amber)
                }
                .buttonStyle(.plain)

                NavigationLink(destination: WaterLogView()) {
                    quickActionLabel("Water", icon: "drop.fill", color: NexusTheme.Colors.Semantic.blue)
                }
                .buttonStyle(.plain)

                quickActionButton("Coffee", icon: "cup.and.saucer.fill", color: .brown) {
                    logQuick("coffee with milk")
                }

                quickActionButton("Snack", icon: "leaf.fill", color: NexusTheme.Colors.Semantic.purple) {
                    logQuick("had a snack")
                }

                quickActionButton("Weight", icon: "scalemass.fill", color: NexusTheme.Colors.Semantic.amber) {
                    isInputFocused = true
                    inputText = "weight "
                }
            }
        }
    }

    private func quickActionLabel(_ title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(NexusTheme.Colors.textPrimary)
        }
        .frame(minWidth: 80)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.lg)
    }

    private func quickActionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            NexusTheme.Haptics.light()
            action()
        } label: {
            quickActionLabel(title, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        ThemePrimaryButton(
            isLoading ? "Logging..." : "Log It",
            icon: "paperplane.fill",
            isLoading: isLoading,
            isDisabled: inputText.isEmpty || isLoading
        ) {
            submitLog()
        }
    }

    // MARK: - Actions

    private func submitLog() {
        guard !inputText.isEmpty else { return }

        haptics.impactOccurred()
        isInputFocused = false
        isLoading = true

        Task {
            do {
                let response = try await viewModel.logUniversal(inputText)
                isLoading = false
                successHaptics.notificationOccurred(.success)
                resultMessage = response.message ?? "Logged successfully"
                showSuccess = true
            } catch {
                isLoading = false
                successHaptics.notificationOccurred(.error)
                resultMessage = error.localizedDescription
                showSuccess = true
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

#Preview {
    QuickLogView(viewModel: DashboardViewModel())
}
