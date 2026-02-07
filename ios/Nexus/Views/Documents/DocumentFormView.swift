import SwiftUI
import UIKit

struct DocumentFormView: View {
    @ObservedObject var viewModel: DocumentsViewModel
    @Binding var isPresented: Bool
    var editingDocument: Document?

    @State private var docType: DocumentType = .passport
    @State private var label = ""
    @State private var issuer = ""
    @State private var issuingCountry = ""
    @State private var docNumber = ""
    @State private var issueDate = Date()
    @State private var hasIssueDate = false
    @State private var expiryDate = Date()
    @State private var notes = ""
    @State private var remindersEnabled = true
    @State private var isSaving = false

    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private let successHaptics = UINotificationFeedbackGenerator()

    private var isEditing: Bool { editingDocument != nil }

    var body: some View {
        Form {
            Section("Document Info") {
                Picker("Type", selection: $docType) {
                    ForEach(DocumentType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                TextField("Label", text: $label)

                TextField("Issuer", text: $issuer)

                TextField("Country", text: $issuingCountry)

                TextField("Document Number", text: $docNumber)
            }

            Section("Dates") {
                Toggle("Has Issue Date", isOn: $hasIssueDate)

                if hasIssueDate {
                    DatePicker("Issue Date", selection: $issueDate, displayedComponents: .date)
                }

                DatePicker("Expiry Date", selection: $expiryDate, displayedComponents: .date)
            }

            Section("Options") {
                Toggle("Expiry Reminders", isOn: $remindersEnabled)

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Document" : "New Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { isPresented = false }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Save" : "Add") {
                    Task { await save() }
                }
                .disabled(label.isEmpty || isSaving)
                .fontWeight(.semibold)
            }
        }
        .onAppear { populateFromEditing() }
        .interactiveDismissDisabled(isSaving)
    }

    private func populateFromEditing() {
        guard let doc = editingDocument else { return }
        docType = DocumentType(rawValue: doc.docType) ?? .other
        label = doc.label
        issuer = doc.issuer ?? ""
        issuingCountry = doc.issuingCountry ?? ""
        docNumber = doc.docNumber ?? ""
        notes = doc.notes ?? ""
        remindersEnabled = doc.remindersEnabled

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        if let issueDateStr = doc.issueDate, let d = df.date(from: issueDateStr) {
            issueDate = d
            hasIssueDate = true
        }
        if let d = df.date(from: doc.expiryDate) {
            expiryDate = d
        }
    }

    private func save() async {
        haptics.impactOccurred()
        isSaving = true
        defer { isSaving = false }

        if let doc = editingDocument {
            let success = await viewModel.updateDocument(
                id: doc.id,
                docType: docType.rawValue,
                label: label,
                issuer: issuer.isEmpty ? nil : issuer,
                issuingCountry: issuingCountry.isEmpty ? nil : issuingCountry,
                docNumber: docNumber.isEmpty ? nil : docNumber,
                issueDate: hasIssueDate ? dateString(issueDate) : nil,
                expiryDate: dateString(expiryDate),
                notes: notes.isEmpty ? nil : notes,
                remindersEnabled: remindersEnabled
            )
            if success {
                successHaptics.notificationOccurred(.success)
                isPresented = false
            } else {
                successHaptics.notificationOccurred(.error)
            }
        } else {
            let success = await viewModel.createDocument(
                docType: docType.rawValue,
                label: label,
                issuer: issuer,
                issuingCountry: issuingCountry,
                docNumber: docNumber,
                issueDate: hasIssueDate ? issueDate : nil,
                expiryDate: expiryDate,
                notes: notes,
                remindersEnabled: remindersEnabled
            )
            if success {
                successHaptics.notificationOccurred(.success)
                isPresented = false
            } else {
                successHaptics.notificationOccurred(.error)
            }
        }
    }

    private func dateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}
