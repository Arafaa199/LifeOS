import SwiftUI

struct DocumentsListView: View {
    @ObservedObject var viewModel: DocumentsViewModel
    @State private var showingAddSheet = false
    @State private var selectedDocument: Document?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.documents.isEmpty {
                ProgressView("Loading documents...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.documents.isEmpty {
                emptyState
            } else {
                documentList
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationView {
                DocumentFormView(viewModel: viewModel, isPresented: $showingAddSheet)
            }
        }
        .sheet(item: $selectedDocument) { doc in
            NavigationView {
                DocumentDetailView(viewModel: viewModel, document: doc)
            }
        }
        .refreshable {
            await viewModel.loadDocuments()
        }
        .task {
            if viewModel.documents.isEmpty {
                await viewModel.loadDocuments()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Documents")
                .font(.headline)
            Text("Track your passports, IDs, visas, and cards with expiry reminders.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Add Document") {
                showingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var documentList: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            if !viewModel.expiringSoon.isEmpty {
                Section("Expiring Soon") {
                    ForEach(viewModel.expiringSoon) { doc in
                        DocumentRow(document: doc)
                            .onTapGesture { selectedDocument = doc }
                    }
                }
            }

            if !viewModel.activeDocuments.isEmpty {
                Section("Active") {
                    ForEach(viewModel.activeDocuments) { doc in
                        DocumentRow(document: doc)
                            .onTapGesture { selectedDocument = doc }
                    }
                }
            }

            if !viewModel.expiredDocuments.isEmpty {
                Section("Expired") {
                    ForEach(viewModel.expiredDocuments) { doc in
                        DocumentRow(document: doc)
                            .onTapGesture { selectedDocument = doc }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct DocumentRow: View {
    let document: Document

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.docTypeIcon)
                .font(.title3)
                .foregroundColor(urgencyColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.label)
                    .font(.body)
                    .fontWeight(.medium)
                Text(document.docTypeLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            UrgencyBadge(urgency: document.urgency, daysUntilExpiry: document.daysUntilExpiry)
        }
        .contentShape(Rectangle())
    }

    private var urgencyColor: Color {
        switch document.urgency {
        case "expired": return .red
        case "critical": return .orange
        case "warning": return .yellow
        default: return .green
        }
    }
}

struct UrgencyBadge: View {
    let urgency: String
    let daysUntilExpiry: Int

    var body: some View {
        Text(badgeText)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.15))
            .foregroundColor(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeText: String {
        switch urgency {
        case "expired": return "Expired"
        case "critical", "warning": return "\(daysUntilExpiry)d"
        default: return "\(daysUntilExpiry)d"
        }
    }

    private var badgeColor: Color {
        switch urgency {
        case "expired": return .red
        case "critical": return .orange
        case "warning": return .yellow
        default: return .green
        }
    }
}
