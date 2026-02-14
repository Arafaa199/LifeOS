import SwiftUI
import UIKit
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "water-log")

struct WaterLogView: View {
    @State private var isLogging = false
    @State private var loggedAmount: Int?
    @State private var errorMessage: String?
    @State private var customAmount = ""

    @Environment(\.dismiss) private var dismiss

    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private let successHaptics = UINotificationFeedbackGenerator()

    private let presets: [(label: String, ml: Int)] = [
        ("250 ml", 250),
        ("500 ml", 500),
        ("750 ml", 750),
    ]

    var body: some View {
        VStack(spacing: NexusTheme.Spacing.xl) {
            Spacer()

            // Icon
            Image(systemName: "drop.fill")
                .font(.system(size: 64))
                .foregroundColor(NexusTheme.Colors.Semantic.blue)

            Text("Log Water")
                .font(.title2.weight(.semibold))
                .foregroundColor(NexusTheme.Colors.textPrimary)

            // Preset buttons
            HStack(spacing: NexusTheme.Spacing.md) {
                ForEach(presets, id: \.ml) { preset in
                    presetButton(preset.label, amount: preset.ml)
                }
            }
            .padding(.horizontal, NexusTheme.Spacing.lg)

            // Custom amount
            HStack(spacing: NexusTheme.Spacing.sm) {
                TextField("Custom", text: $customAmount)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)

                Text("ml")
                    .font(.subheadline)
                    .foregroundColor(NexusTheme.Colors.textSecondary)

                Button {
                    if let amount = Int(customAmount), amount > 0 {
                        logWater(amount: amount)
                    }
                } label: {
                    Text("Log")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, NexusTheme.Spacing.lg)
                        .padding(.vertical, NexusTheme.Spacing.sm)
                        .background(NexusTheme.Colors.Semantic.blue)
                        .cornerRadius(NexusTheme.Radius.md)
                }
                .disabled(Int(customAmount) ?? 0 <= 0 || isLogging)
            }

            // Status
            if isLogging {
                ProgressView()
                    .tint(NexusTheme.Colors.Semantic.blue)
            } else if let amount = loggedAmount {
                HStack(spacing: NexusTheme.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(NexusTheme.Colors.Semantic.green)
                    Text("\(amount) ml logged")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(NexusTheme.Colors.Semantic.green)
                }
                .transition(.scale.combined(with: .opacity))
            } else if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(NexusTheme.Colors.Semantic.red)
            }

            Spacer()
            Spacer()
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle("Water")
        .navigationBarTitleDisplayMode(.large)
    }

    private func presetButton(_ label: String, amount: Int) -> some View {
        Button {
            logWater(amount: amount)
        } label: {
            VStack(spacing: NexusTheme.Spacing.xs) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 20))
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(NexusTheme.Colors.Semantic.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, NexusTheme.Spacing.lg)
            .background(NexusTheme.Colors.Semantic.blue.opacity(0.1))
            .cornerRadius(NexusTheme.Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.lg)
                    .stroke(NexusTheme.Colors.Semantic.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLogging)
    }

    private func logWater(amount: Int) {
        haptics.impactOccurred()
        isLogging = true
        errorMessage = nil
        loggedAmount = nil

        Task {
            do {
                let response = try await NutritionAPI.shared.logWater(amountMl: amount)
                await MainActor.run {
                    isLogging = false
                    if response.success {
                        successHaptics.notificationOccurred(.success)
                        withAnimation(.spring(duration: 0.3)) {
                            loggedAmount = amount
                        }
                        // Auto-dismiss after brief display
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            dismiss()
                        }
                    } else {
                        successHaptics.notificationOccurred(.error)
                        errorMessage = "Failed to log water"
                    }
                }
            } catch {
                logger.error("Water log failed: \(error.localizedDescription)")
                await MainActor.run {
                    isLogging = false
                    successHaptics.notificationOccurred(.error)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        WaterLogView()
    }
}
