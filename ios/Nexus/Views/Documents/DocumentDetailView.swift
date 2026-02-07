import SwiftUI

struct DocumentDetailView: View {
    @ObservedObject var viewModel: DocumentsViewModel
    let document: Document
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    @State private var showingRenewSheet = false
    @State private var showingDeleteAlert = false
    @State private var isRecreatingReminders = false

    var body: some View {
        List {
            detailsSection
            if document.notes != nil {
                notesSection
            }
            remindersSection
            actionsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NexusTheme.Colors.background)
        .navigationTitle(document.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingEditSheet = true }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationView {
                DocumentFormView(viewModel: viewModel, isPresented: $showingEditSheet, editingDocument: document)
            }
        }
        .sheet(isPresented: $showingRenewSheet) {
            NavigationView {
                RenewDocumentView(viewModel: viewModel, document: document, isPresented: $showingRenewSheet)
            }
        }
        .alert("Delete Document", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.deleteDocument(id: document.id) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the document and its reminders. This cannot be undone.")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            row("Type", value: document.docTypeLabel)
            row("Label", value: document.label)
            if let issuer = document.issuer {
                row("Issuer", value: issuer)
            }
            if let country = document.issuingCountry {
                row("Country", value: country)
            }
            if let num = document.maskedDocNumber {
                row("Number", value: num)
            }
            if let issueDate = document.issueDate {
                row("Issue Date", value: formatDate(issueDate))
            }
            row("Expiry Date", value: formatDate(document.expiryDate))

            HStack {
                Text("Status")
                    .foregroundColor(.secondary)
                Spacer()
                UrgencyBadge(urgency: document.urgency, daysUntilExpiry: document.daysUntilExpiry)
            }

            if document.renewalCount > 0 {
                NavigationLink {
                    DocumentRenewalHistoryView(viewModel: viewModel, documentId: document.id, renewalCount: document.renewalCount)
                } label: {
                    HStack {
                        Text("Renewals")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(document.renewalCount)")
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            Text(document.notes ?? "")
                .font(.body)
        }
    }

    private var remindersSection: some View {
        Section("Reminders") {
            HStack {
                Text("Reminders")
                    .foregroundColor(.secondary)
                Spacer()
                Text(document.remindersEnabled ? "Enabled" : "Disabled")
                    .foregroundColor(document.remindersEnabled ? NexusTheme.Colors.Semantic.green : .secondary)
            }

            Button {
                Task {
                    isRecreatingReminders = true
                    await viewModel.recreateReminders(id: document.id)
                    isRecreatingReminders = false
                }
            } label: {
                HStack {
                    Text("Recreate Reminders")
                    Spacer()
                    if isRecreatingReminders {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .disabled(isRecreatingReminders)
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                showingRenewSheet = true
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Mark as Renewed")
                }
            }
            .accessibilityHint("Opens renewal form to update expiry date")

            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Document")
                }
            }
            .accessibilityHint("Permanently removes this document and its reminders")
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
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
