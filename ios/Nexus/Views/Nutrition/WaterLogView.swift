import SwiftUI
import UIKit
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "water-log")

struct WaterLogView: View {
    @State private var isLogging = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private let successHaptics = UINotificationFeedbackGenerator()

    var body: some View {
        VStack(spacing: NexusTheme.Spacing.xxl) {
            Spacer()

            Image(systemName: "drop.fill")
                .font(.system(size: 72))
                .foregroundColor(NexusTheme.Colors.Semantic.blue)

            Text("Log Water")
                .font(.title2.weight(.semibold))
                .foregroundColor(NexusTheme.Colors.textPrimary)

            Text("Tap below to record a water intake")
                .font(.subheadline)
                .foregroundColor(NexusTheme.Colors.textSecondary)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(NexusTheme.Colors.Semantic.red)
            }

            Spacer()

            Button {
                logWater()
            } label: {
                HStack(spacing: NexusTheme.Spacing.sm) {
                    if isLogging {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "drop.fill")
                    }
                    Text("Log Water")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, NexusTheme.Spacing.md)
                .background(NexusTheme.Colors.Semantic.blue)
                .cornerRadius(NexusTheme.Radius.md)
            }
            .disabled(isLogging)
            .padding(.horizontal, NexusTheme.Spacing.xl)
            .padding(.bottom, NexusTheme.Spacing.xxxl)
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle("Water")
        .navigationBarTitleDisplayMode(.large)
        .alert("Water Logged", isPresented: $showSuccess) {
            Button("OK", role: .cancel) {}
        }
    }

    private func logWater() {
        haptics.impactOccurred()
        isLogging = true
        errorMessage = nil

        Task {
            do {
                let response = try await HabitsAPI.shared.logWater()
                await MainActor.run {
                    isLogging = false
                    if response.success {
                        successHaptics.notificationOccurred(.success)
                        showSuccess = true
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
