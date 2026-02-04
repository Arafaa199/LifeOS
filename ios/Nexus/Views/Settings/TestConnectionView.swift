import SwiftUI

/// Tests the connection to the Nexus backend
struct TestConnectionView: View {
    @State private var isTesting = false
    @State private var testResult = ""
    @State private var testSuccess = false
    @State private var responseTime: Double? = nil

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 160, height: 160)

                Image(systemName: statusIcon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(statusColor)
                    .symbolEffect(.pulse, isActive: isTesting)
            }

            VStack(spacing: 12) {
                Text(statusTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(testResult.isEmpty ? "Tap the button below to test your connection to the Nexus backend." : testResult)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let time = responseTime {
                    Text("Response time: \(String(format: "%.0f", time))ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }

            Spacer()

            Button(action: testConnection) {
                HStack(spacing: 10) {
                    if isTesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "wifi")
                            .font(.body.weight(.semibold))
                    }
                    Text(isTesting ? "Testing..." : "Test Connection")
                        .fontWeight(.semibold)
                }
            }
            .nexusPrimaryButton(disabled: isTesting)
            .disabled(isTesting)
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Connection Test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusIcon: String {
        if isTesting { return "wifi" }
        if testResult.isEmpty { return "wifi.exclamationmark" }
        return testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        if isTesting { return .nexusPrimary }
        if testResult.isEmpty { return .secondary }
        return testSuccess ? .nexusSuccess : .nexusError
    }

    private var statusTitle: String {
        if isTesting { return "Testing..." }
        if testResult.isEmpty { return "Ready to Test" }
        return testSuccess ? "Connected" : "Connection Failed"
    }

    private func testConnection() {
        isTesting = true
        testResult = ""
        responseTime = nil

        let startTime = Date()

        Task {
            do {
                let response = try await NexusAPI.shared.fetchFinanceSummary()
                let elapsed = Date().timeIntervalSince(startTime) * 1000

                await MainActor.run {
                    isTesting = false
                    testSuccess = response.success
                    responseTime = elapsed

                    if response.success {
                        testResult = "Successfully connected to your Nexus backend. All systems operational."
                    } else {
                        testResult = response.message ?? "Connection established but received an error response."
                    }

                    let haptics = UINotificationFeedbackGenerator()
                    haptics.notificationOccurred(response.success ? .success : .error)
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testSuccess = false
                    testResult = "Could not reach the server. Check your URL and network connection."

                    let haptics = UINotificationFeedbackGenerator()
                    haptics.notificationOccurred(.error)
                }
            }
        }
    }
}
