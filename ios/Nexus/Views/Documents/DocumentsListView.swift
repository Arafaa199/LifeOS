import SwiftUI
import UIKit

struct DocumentsListView: View {
    @ObservedObject var viewModel: DocumentsViewModel
    @State private var showingAddSheet = false
    @State private var selectedDocument: Document?

    private let haptics = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.documents.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading documents...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading documents")
            } else if viewModel.documents.isEmpty {
                emptyState
            } else {
                documentList
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    haptics.impactOccurred()
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add document")
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
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
                .padding(.top, 40)
            
            VStack(spacing: 8) {
                Text("No Documents Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Keep track of important documents like passports, visas, IDs, and cards.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Text("Get expiry reminders so you never miss a renewal.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button {
                haptics.impactOccurred()
                showingAddSheet = true
            } label: {
                Label("Add Your First Document", systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var documentList: some View {
        List {
            // Error display - only show real errors, not false positives
            if let error = viewModel.errorMessage, !error.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.nexusWarning)
                            .imageScale(.medium)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync Issue")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Your documents are stored safely on this device. Pull down to retry syncing.")
                        .font(.caption)
                }
            }

            if !viewModel.expiringSoon.isEmpty {
                Section {
                    ForEach(viewModel.expiringSoon) { doc in
                        DocumentRow(document: doc)
                            .onTapGesture { selectedDocument = doc }
                    }
                } header: {
                    Label("Expiring Soon", systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(.nexusWarning)
                }
            }

            if !viewModel.activeDocuments.isEmpty {
                Section("Active Documents") {
                    ForEach(viewModel.activeDocuments) { doc in
                        DocumentRow(document: doc)
                            .onTapGesture { selectedDocument = doc }
                    }
                }
            }

            if !viewModel.expiredDocuments.isEmpty {
                Section {
                    ForEach(viewModel.expiredDocuments) { doc in
                        DocumentRow(document: doc)
                            .onTapGesture { selectedDocument = doc }
                    }
                } header: {
                    Label("Expired", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.nexusError)
                } footer: {
                    Text("These documents have passed their expiry date and may need renewal.")
                        .font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.nexusBackground)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(document.label), \(document.docTypeLabel), \(urgencyAccessibilityLabel)")
    }

    private var urgencyAccessibilityLabel: String {
        switch document.urgency {
        case "expired": return "expired"
        case "critical": return "expiring in \(document.daysUntilExpiry) days, urgent"
        case "warning": return "expiring in \(document.daysUntilExpiry) days"
        default: return "\(document.daysUntilExpiry) days until expiry"
        }
    }

    private var urgencyColor: Color {
        switch document.urgency {
        case "expired": return .nexusError
        case "critical": return .nexusWarning
        case "warning": return .nexusFood
        default: return .nexusSuccess
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
        case "expired": return .nexusError
        case "critical": return .nexusWarning
        case "warning": return .nexusFood
        default: return .nexusSuccess
        }
    }
}
