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

    // Search + barcode states
    @State private var showFoodSearch = false
    @State private var showBarcodeScanner = false
    @State private var selectedFood: FoodSearchResult?

    @StateObject private var speechRecognizer = SpeechRecognizer()
    private let photoLogger = PhotoFoodLogger.shared
    private let api = NexusAPI.shared
    private let haptics = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptics = UINotificationFeedbackGenerator()

    private var canSubmit: Bool {
        !foodDescription.isEmpty || capturedImage != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Search + Barcode Section
                searchSection

                // Macro Preview (when food selected from search/barcode)
                if let food = selectedFood {
                    macroPreviewCard(food)
                }

                // Meal Type Selector
                mealTypeSection

                // Food Description Input
                descriptionSection

                // Photo Capture Section
                photoCaptureSection

                // Quick Food Buttons
                quickFoodSection

                Spacer(minLength: 20)

                // Submit Button
                submitButton
            }
            .padding()
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle("Log Food")
        .navigationBarTitleDisplayMode(.large)
        .alert("Food Logged", isPresented: $showSuccess) {
            Button("OK", role: .cancel) {
                foodDescription = ""
                capturedImage = nil
                selectedFood = nil
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
        .sheet(isPresented: $showFoodSearch) {
            NavigationView {
                FoodSearchView { food in
                    selectFood(food)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showFoodSearch = false }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showBarcodeScanner) {
            BarcodeScannerView(
                onResult: { food in
                    selectFood(food)
                },
                onManualEntry: { barcode in
                    foodDescription = "Barcode: \(barcode) — "
                }
            )
        }
    }

    // MARK: - Search Section

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find Food")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: { showFoodSearch = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Search Foods")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(NexusTheme.Colors.Semantic.amber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NexusTheme.Colors.Semantic.amber.opacity(0.12))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { showBarcodeScanner = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Scan")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(NexusTheme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NexusTheme.Colors.accent.opacity(0.12))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .nexusCard()
    }

    // MARK: - Macro Preview Card

    private func macroPreviewCard(_ food: FoodSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    if let brand = food.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: { selectedFood = nil; foodDescription = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 0) {
                macroColumn("Calories", value: food.calories_per_100g, format: "%.0f", unit: "", color: NexusTheme.Colors.Semantic.amber)
                macroColumn("Protein", value: food.protein_per_100g, format: "%.1f", unit: "g", color: NexusTheme.Colors.accent)
                macroColumn("Carbs", value: food.carbs_per_100g, format: "%.1f", unit: "g", color: NexusTheme.Colors.Semantic.amber)
                macroColumn("Fat", value: food.fat_per_100g, format: "%.1f", unit: "g", color: .yellow)
            }

            if let serving = food.serving_description, !serving.isEmpty {
                Text("Per 100g  |  Serving: \(serving)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Per 100g")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .nexusCard()
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(NexusTheme.Colors.Semantic.amber.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func macroColumn(_ label: String, value: Double?, format: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            if let v = value {
                Text(String(format: format, v) + unit)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            } else {
                Text("—")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Meal Type Section

    private var mealTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meal Type")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(MealType.allCases) { meal in
                    Button(action: { selectedMeal = meal }) {
                        VStack(spacing: 6) {
                            Image(systemName: meal.icon)
                                .font(.system(size: 20, weight: .medium))

                            Text(meal.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(selectedMeal == meal ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedMeal == meal ?
                            NexusTheme.Colors.Semantic.amber :
                            Color(.systemBackground)
                        )
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedMeal == meal ? NexusTheme.Colors.Semantic.amber : Color(.systemGray4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .nexusCard()
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What did you eat?")
                    .font(.headline)

                Spacer()

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
                TextEditor(text: speechRecognizer.isRecording ? $speechRecognizer.transcript : $foodDescription)
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(speechRecognizer.isRecording ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.accent.opacity(0.3), lineWidth: speechRecognizer.isRecording ? 2 : 1)
                    )
                    .focused($isInputFocused)
                    .disabled(speechRecognizer.isRecording)

                if foodDescription.isEmpty && !speechRecognizer.isRecording {
                    Text("Describe your meal...")
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

            Text("Examples: \"2 eggs and avocado toast\", \"chicken stir fry\"")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .nexusCard()
    }

    // MARK: - Photo Capture Section

    private var photoCaptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Or snap a photo")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: { showCameraPicker = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Camera")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(NexusTheme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NexusTheme.Colors.accent.opacity(0.12))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { showPhotoPicker = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Library")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(NexusTheme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NexusTheme.Colors.accent.opacity(0.12))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if let image = capturedImage {
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(NexusTheme.Colors.Semantic.green)
                            Text("Photo ready")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        Text("AI will analyze and estimate nutrition")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { capturedImage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(NexusTheme.Colors.Semantic.green.opacity(0.08))
                .cornerRadius(12)
            }
        }
        .nexusCard()
    }

    // MARK: - Quick Food Section

    private var quickFoodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    QuickFoodChip(title: "Coffee", icon: "cup.and.saucer") {
                        addQuickFood("coffee with milk")
                    }
                    QuickFoodChip(title: "Eggs", icon: "oval") {
                        addQuickFood("2 eggs")
                    }
                    QuickFoodChip(title: "Protein Shake", icon: "bolt") {
                        addQuickFood("protein shake")
                    }
                    QuickFoodChip(title: "Chicken & Rice", icon: "fork.knife") {
                        addQuickFood("chicken and rice")
                    }
                    QuickFoodChip(title: "Oats", icon: "leaf") {
                        addQuickFood("oatmeal")
                    }
                }
            }
        }
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button(action: submitFoodLog) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: capturedImage != nil ? "camera.fill" : "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                }
                Text(isLoading ? "Processing..." : (capturedImage != nil ? "Analyze Photo" : "Log Food"))
                    .fontWeight(.semibold)
            }
        }
        .nexusAccentButton(disabled: !canSubmit || isLoading)
        .disabled(!canSubmit || isLoading)
    }

    // MARK: - Actions

    private func selectFood(_ food: FoodSearchResult) {
        selectedFood = food
        foodDescription = food.name
        if let brand = food.brand, !brand.isEmpty {
            foodDescription += " (\(brand))"
        }
    }

    private func submitFoodLog() {
        guard !foodDescription.isEmpty || capturedImage != nil else { return }

        haptics.impactOccurred()
        isInputFocused = false
        isLoading = true

        Task {
            do {
                let response: NexusResponse

                if let image = capturedImage {
                    let resized = photoLogger.resizeImage(image, maxDimension: 1024)
                    guard let imageData = photoLogger.compressImage(resized, maxSizeKB: 500) else {
                        throw APIError.invalidResponse
                    }

                    let context = foodDescription.isEmpty ? nil : "\(foodDescription) for \(selectedMeal.rawValue.lowercased())"
                    response = try await photoLogger.logFoodFromPhoto(imageData, additionalContext: context)
                } else {
                    let fullDescription = "\(foodDescription) for \(selectedMeal.rawValue.lowercased())"
                    response = try await api.logFood(
                        fullDescription,
                        foodId: selectedFood?.id,
                        mealType: selectedMeal.rawValue.lowercased()
                    )
                }

                await MainActor.run {
                    isLoading = false
                    successHaptics.notificationOccurred(.success)
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
                    successHaptics.notificationOccurred(.error)
                    resultMessage = "Error: \(error.localizedDescription)"
                    showSuccess = true
                }
            }
        }
    }

    private func addQuickFood(_ food: String) {
        selectedFood = nil
        if foodDescription.isEmpty {
            foodDescription = food
        } else {
            foodDescription += ", \(food)"
        }
    }

    private func toggleVoiceInput() {
        if speechRecognizer.isRecording {
            haptics.impactOccurred()
            speechRecognizer.stopRecording()

            if !speechRecognizer.transcript.isEmpty {
                foodDescription = speechRecognizer.transcript
            }
        } else {
            haptics.impactOccurred()
            foodDescription = ""
            selectedFood = nil

            speechRecognizer.requestAuthorization { authorized in
                if authorized {
                    speechRecognizer.startRecording { result in
                        switch result {
                        case .success(let transcript):
                            if !transcript.isEmpty {
                                foodDescription = transcript
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

// MARK: - Supporting Views

struct QuickFoodChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(NexusTheme.Colors.Semantic.amber.opacity(0.12))
            .foregroundColor(NexusTheme.Colors.Semantic.amber)
            .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

enum MealType: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "leaf"
        }
    }
}

struct QuickFoodButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        QuickFoodChip(title: title, icon: icon, action: action)
    }
}

#Preview {
    NavigationView {
        FoodLogView(viewModel: DashboardViewModel())
    }
}
