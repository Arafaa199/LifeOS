import SwiftUI

/// API configuration (webhook URL, API key)
struct ConfigurationSection: View {
    @Binding var webhookURL: String
    @Binding var apiKey: String
    var onSave: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Webhook URL", systemImage: "link")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("https://n8n.rfanw", text: $webhookURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(12)
                    .background(Color.nexusCardBackground)
                    .cornerRadius(10)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Label("API Key", systemImage: "key")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                SecureField("Enter your API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.nexusCardBackground)
                    .cornerRadius(10)
            }
            .padding(.vertical, 4)

            Button(action: onSave) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Configuration")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.white)
            .background(webhookURL.isEmpty ? Color.nexusPrimary.opacity(0.4) : Color.nexusPrimary)
            .cornerRadius(10)
            .disabled(webhookURL.isEmpty)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Configuration")
        }
    }
}
