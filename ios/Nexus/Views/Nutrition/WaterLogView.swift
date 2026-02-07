import SwiftUI
import UIKit

struct WaterLogView: View {
    @StateObject private var viewModel = NutritionViewModel()
    @State private var customAmount: String = ""
    @State private var showCustomInput = false
    @State private var isLogging = false
    @State private var showSuccess = false
    @State private var lastLoggedAmount: Int = 0

    @Environment(\.dismiss) private var dismiss

    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private let successHaptics = UINotificationFeedbackGenerator()

    private let presets: [(String, Int)] = [
        ("Glass", 250),
        ("Bottle", 500),
        ("Large", 750),
        ("Liter", 1000)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                progressSection
                presetsSection
                customSection
                historySection
            }
            .padding()
        }
        .background(Color.nexusBackground)
        .navigationTitle("Log Water")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadHistory()
        }
        .alert("Logged", isPresented: $showSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(lastLoggedAmount)ml added. Total: \(viewModel.totalWaterToday)ml")
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: viewModel.waterProgress)
                    .stroke(
                        LinearGradient(
                            colors: [.nexusWater, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: viewModel.waterProgress)

                VStack(spacing: 4) {
                    Text("\(viewModel.totalWaterToday)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("ml")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Text(viewModel.waterProgressText)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if viewModel.totalWaterToday >= NutritionViewModel.waterGoalMl {
                Label("Goal reached!", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.nexusSuccess)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(presets, id: \.1) { preset in
                    Button {
                        logWater(preset.1)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "drop.fill")
                                .font(.title2)
                                .foregroundColor(.nexusWater)

                            Text(preset.0)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)

                            Text("\(preset.1)ml")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.nexusCardBackground)
                        .cornerRadius(12)
                    }
                    .disabled(isLogging)
                }
            }
        }
    }

    // MARK: - Custom Section

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    showCustomInput.toggle()
                }
            } label: {
                HStack {
                    Text("Custom Amount")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: showCustomInput ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }

            if showCustomInput {
                HStack(spacing: 12) {
                    TextField("Amount", text: $customAmount)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)

                    Text("ml")
                        .foregroundColor(.secondary)

                    Button {
                        if let amount = Int(customAmount), amount > 0 {
                            logWater(amount)
                            customAmount = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.nexusWater)
                    }
                    .disabled(Int(customAmount) == nil || Int(customAmount)! <= 0 || isLogging)
                }
                .padding()
                .background(Color.nexusCardBackground)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Log")
                .font(.headline)

            if viewModel.waterEntries.isEmpty {
                Text("No water logged yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.waterEntries) { entry in
                        HStack {
                            Image(systemName: "drop.fill")
                                .foregroundColor(.nexusWater)

                            Text("\(entry.amount_ml)ml")
                                .font(.subheadline.weight(.medium))

                            Spacer()

                            Text(entry.formattedTime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.nexusCardBackground)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func logWater(_ amount: Int) {
        haptics.impactOccurred()
        isLogging = true
        lastLoggedAmount = amount

        Task {
            let success = await viewModel.logWater(amountML: amount)
            isLogging = false

            if success {
                successHaptics.notificationOccurred(.success)
                showSuccess = true
                await viewModel.loadHistory()
            } else {
                successHaptics.notificationOccurred(.error)
            }
        }
    }
}

#Preview {
    NavigationView {
        WaterLogView()
    }
}
