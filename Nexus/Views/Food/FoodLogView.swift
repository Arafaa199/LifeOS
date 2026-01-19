import SwiftUI
import Speech
import PhotosUI

struct FoodLogView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var foodDescription = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var resultMessage = ""
    @State private var selectedMeal: MealType = .snack
    @FocusState private var isInputFocused: Bool

    // Photo capture states
    @State private var showCameraPicker = false
    @State private var showPhotoPicker = false
    @State private var capturedImage: UIImage?
    @State private var isProcessingPhoto = false

    @StateObject private var speechRecognizer = SpeechRecognizer()
    private let photoLogger = PhotoFoodLogger.shared
    private let api = NexusAPI.shared
    private let haptics = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptics = UINotificationFeedbackGenerator()

    // Can submit if we have text OR a captured photo
    private var canSubmit: Bool {
        !foodDescription.isEmpty || capturedImage != nil
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Meal Type Selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meal Type")
                            .font(.headline)

                        Picker("Meal Type", selection: $selectedMeal) {
                            ForEach(MealType.allCases) { meal in
                                Text(meal.rawValue).tag(meal)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)

                    // Food Description Input
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("What did you eat?")
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
                            TextEditor(text: speechRecognizer.isRecording ? $speechRecognizer.transcript : $foodDescription)
                                .frame(minHeight: 120)
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
                            Text("Examples: \"2 eggs and avocado toast\", \"chicken stir fry, serving 2 of 5\", \"burger and fries, estimate it\"")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Describe what you ate, tap mic when done")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal)

                    // Photo Capture Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Snap a Photo")
                            .font(.headline)
                            .padding(.horizontal)

                        HStack(spacing: 12) {
                            // Camera button
                            Button(action: { showCameraPicker = true }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "camera.fill")
                                        .font(.title2)
                                    Text("Camera")
                                        .font(.caption)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Photo library button
                            Button(action: { showPhotoPicker = true }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.title2)
                                    Text("Library")
                                        .font(.caption)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal)

                        // Show captured image preview
                        if let image = capturedImage {
                            HStack {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Photo ready")
                                        .font(.subheadline)
                                        .bold()
                                    Text("Add optional notes above, then tap Log Food")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button(action: { capturedImage = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        Text("AI will identify food and estimate nutrition")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }

                    // Quick Food Buttons
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quick Add")
                            .font(.headline)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                QuickFoodButton(title: "Coffee", icon: "cup.and.saucer") {
                                    addQuickFood("coffee with milk")
                                }
                                QuickFoodButton(title: "Eggs", icon: "circle") {
                                    addQuickFood("2 eggs")
                                }
                                QuickFoodButton(title: "Protein Shake", icon: "bolt") {
                                    addQuickFood("protein shake")
                                }
                                QuickFoodButton(title: "Chicken & Rice", icon: "fork.knife") {
                                    addQuickFood("chicken and rice")
                                }
                                QuickFoodButton(title: "Oats", icon: "circle.grid.3x3") {
                                    addQuickFood("oatmeal")
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Spacer()

                    // Submit Button
                    Button(action: submitFoodLog) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: capturedImage != nil ? "camera.fill" : "checkmark.circle.fill")
                            }
                            Text(isLoading ? "Processing..." : (capturedImage != nil ? "Log Photo" : "Log Food"))
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSubmit ? Color.orange : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canSubmit || isLoading)
                    .padding(.horizontal)
                }
                .padding(.top)
            }
            .navigationTitle("Log Food")
            .alert("Food Logged", isPresented: $showSuccess) {
                Button("OK", role: .cancel) {
                    foodDescription = ""
                    capturedImage = nil
                }
            } message: {
                Text(resultMessage)
            }
            .fullScreenCover(isPresented: $showCameraPicker) {
                PhotoPicker(image: $capturedImage, sourceType: .camera)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(image: $capturedImage, sourceType: .photoLibrary)
            }
        }
    }

    private func submitFoodLog() {
        // Allow submission if we have text OR a photo
        guard !foodDescription.isEmpty || capturedImage != nil else { return }

        // Haptic feedback
        haptics.impactOccurred()

        // Dismiss keyboard
        isInputFocused = false

        isLoading = true

        Task {
            do {
                let response: NexusResponse

                if let image = capturedImage {
                    // Photo-based logging
                    let resized = photoLogger.resizeImage(image, maxDimension: 1024)
                    guard let imageData = photoLogger.compressImage(resized, maxSizeKB: 500) else {
                        throw APIError.invalidResponse
                    }

                    // Include any text description as context
                    let context = foodDescription.isEmpty ? nil : "\(foodDescription) for \(selectedMeal.rawValue.lowercased())"
                    response = try await photoLogger.logFoodFromPhoto(imageData, additionalContext: context)
                } else {
                    // Text-based logging (use offline-capable API)
                    let fullDescription = "\(foodDescription) for \(selectedMeal.rawValue.lowercased())"
                    response = try await api.logFoodOffline(fullDescription)
                }

                await MainActor.run {
                    isLoading = false
                    // Success haptic
                    successHaptics.notificationOccurred(.success)

                    // Update dashboard
                    viewModel.updateSummaryAfterLog(type: .food, response: response)

                    if let data = response.data, let calories = data.calories, let protein = data.protein {
                        resultMessage = "Logged \(selectedMeal.rawValue): \(calories) cal, \(String(format: "%.1f", protein))g protein"
                    } else {
                        resultMessage = response.message ?? "Food logged successfully"
                    }
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false

                    // Error haptic
                    successHaptics.notificationOccurred(.error)

                    resultMessage = "Error: \(error.localizedDescription)"
                    showSuccess = true
                }
            }
        }
    }

    private func addQuickFood(_ food: String) {
        if foodDescription.isEmpty {
            foodDescription = food
        } else {
            foodDescription += ", \(food)"
        }
    }

    private func toggleVoiceInput() {
        if speechRecognizer.isRecording {
            // Stop recording
            haptics.impactOccurred()
            speechRecognizer.stopRecording()

            // Transfer transcript to foodDescription
            if !speechRecognizer.transcript.isEmpty {
                foodDescription = speechRecognizer.transcript
            }
        } else {
            // Start recording
            haptics.impactOccurred()
            foodDescription = "" // Clear previous input

            speechRecognizer.requestAuthorization { authorized in
                if authorized {
                    speechRecognizer.startRecording { result in
                        switch result {
                        case .success(let transcript):
                            // Final transcript
                            if !transcript.isEmpty {
                                foodDescription = transcript
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

enum MealType: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"

    var id: String { self.rawValue }
}

struct QuickFoodButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .padding()
            .frame(minWidth: 80)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}


#Preview {
    FoodLogView(viewModel: DashboardViewModel())
}
