import SwiftUI

struct RenewDocumentView: View {
    @ObservedObject var viewModel: DocumentsViewModel
    let document: Document
    @Binding var isPresented: Bool

    @State private var newExpiryDate = Date()
    @State private var newDocNumber = ""
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("Current") {
                HStack {
                    Text("Document")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(document.label)
                }
                HStack {
                    Text("Current Expiry")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDate(document.expiryDate))
                }
            }

            Section("Renewal") {
                DatePicker("New Expiry Date", selection: $newExpiryDate, displayedComponents: .date)

                TextField("New Document Number (optional)", text: $newDocNumber)

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Renew Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { isPresented = false }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Renew") {
                    Task { await renew() }
                }
                .disabled(isSaving)
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            if let d = df.date(from: document.expiryDate) {
                newExpiryDate = Calendar.current.date(byAdding: .year, value: 1, to: d) ?? Date()
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func renew() async {
        isSaving = true
        defer { isSaving = false }

        let success = await viewModel.renewDocument(
            id: document.id,
            newExpiryDate: newExpiryDate,
            newDocNumber: newDocNumber,
            notes: notes
        )
        if success {
            isPresented = false
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
}
