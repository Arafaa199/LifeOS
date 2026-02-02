import SwiftUI

struct DocumentRenewalHistoryView: View {
    @ObservedObject var viewModel: DocumentsViewModel
    let documentId: Int
    let renewalCount: Int

    var body: some View {
        Group {
            if viewModel.isLoadingHistory {
                ProgressView("Loading history...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.renewalHistory.isEmpty {
                Text("No renewal records found.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.renewalHistory) { renewal in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(formatDate(renewal.oldExpiryDate))
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatDate(renewal.newExpiryDate))
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)

                        if let oldNum = renewal.oldDocNumber, let newNum = renewal.newDocNumber, oldNum != newNum {
                            HStack {
                                Text("Doc #:")
                                    .foregroundColor(.secondary)
                                Text(maskNumber(oldNum))
                                    .foregroundColor(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(maskNumber(newNum))
                            }
                            .font(.caption)
                        }

                        if let notes = renewal.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(formatTimestamp(renewal.renewedAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Renewal History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadRenewalHistory(documentId: documentId)
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: dateStr) else { return dateStr }
        let output = DateFormatter()
        output.dateStyle = .medium
        return output.string(from: date)
    }

    private func formatTimestamp(_ ts: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: ts) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: ts) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return ts
    }

    private func maskNumber(_ num: String) -> String {
        guard num.count > 4 else { return num }
        let visible = String(num.suffix(4))
        let masked = String(repeating: "*", count: num.count - 4)
        return masked + visible
    }
}
