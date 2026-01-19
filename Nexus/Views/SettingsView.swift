import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var webhookURL: String = ""
    @State private var showingSaveConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Configuration")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Webhook Base URL")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("https://n8n.rfanw", text: $webhookURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    Button("Save Settings") {
                        settings.webhookBaseURL = webhookURL
                        showingSaveConfirmation = true
                    }
                    .disabled(webhookURL.isEmpty)
                }

                Section(header: Text("About")) {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "1")

                    Link(destination: URL(string: "https://github.com/yourusername/nexus")!) {
                        HStack {
                            Text("Documentation")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                }

                Section(header: Text("Quick Actions")) {
                    NavigationLink(destination: TestConnectionView()) {
                        Label("Test Connection", systemImage: "wifi")
                    }

                    Button(role: .destructive) {
                        // Clear all local data
                    } label: {
                        Label("Clear Local Data", systemImage: "trash")
                    }
                }

                Section(header: Text("Integrations")) {
                    NavigationLink(destination: Text("Widget Settings")) {
                        Label("Configure Widgets", systemImage: "square.grid.2x2")
                    }

                    NavigationLink(destination: Text("Siri Shortcuts")) {
                        Label("Siri Shortcuts", systemImage: "mic.fill")
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                webhookURL = settings.webhookBaseURL
            }
            .alert("Settings Saved", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your webhook URL has been updated.")
            }
        }
    }
}

struct TestConnectionView: View {
    @State private var isTesting = false
    @State private var testResult = ""
    @State private var testSuccess = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: testSuccess ? "checkmark.circle.fill" : "wifi.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(testSuccess ? .green : .orange)

            Text(testResult.isEmpty ? "Test your Nexus connection" : testResult)
                .multilineTextAlignment(.center)
                .padding()

            Button(action: testConnection) {
                HStack {
                    if isTesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(isTesting ? "Testing..." : "Test Connection")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isTesting)
            .padding()

            Spacer()
        }
        .padding()
        .navigationTitle("Test Connection")
    }

    private func testConnection() {
        isTesting = true
        testResult = ""

        Task {
            do {
                // Try a simple log
                let response = try await NexusAPI.shared.logUniversal("test connection")
                await MainActor.run {
                    isTesting = false
                    testSuccess = response.success
                    testResult = response.success ?
                        "✓ Connected successfully!" :
                        "⚠ Connection failed: \(response.message ?? "Unknown error")"
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testSuccess = false
                    testResult = "✗ Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
