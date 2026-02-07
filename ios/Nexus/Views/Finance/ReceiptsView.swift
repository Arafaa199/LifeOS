import SwiftUI
import os

struct ReceiptsView: View {
    @State private var receipts: [Receipt] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedReceipt: Receipt?

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "receipts")

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading receipts...")
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Unable to Load Receipts",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if receipts.isEmpty {
                ContentUnavailableView(
                    "No Receipts",
                    systemImage: "doc.text",
                    description: Text("Receipt data from emails will appear here")
                )
            } else {
                receiptsList
            }
        }
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadReceipts()
        }
        .refreshable {
            await loadReceipts()
        }
        .sheet(item: $selectedReceipt) { receipt in
            ReceiptDetailView(receipt: receipt)
        }
    }

    // MARK: - Receipts List

    private var receiptsList: some View {
        List {
            ForEach(groupedReceipts, id: \.key) { group in
                Section(header: Text(group.key)) {
                    ForEach(group.value) { receipt in
                        ReceiptRow(receipt: receipt)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedReceipt = receipt
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Grouped by Vendor

    private var groupedReceipts: [(key: String, value: [Receipt])] {
        let grouped = Dictionary(grouping: receipts) { $0.displayVendor }
        return grouped.sorted { $0.key < $1.key }
    }

    // MARK: - Load Data

    private func loadReceipts() async {
        isLoading = receipts.isEmpty
        errorMessage = nil

        do {
            let response = try await NexusAPI.shared.fetchReceipts(limit: 100)
            if response.success {
                receipts = response.receipts
                logger.info("[receipts] loaded \(response.receipts.count) receipts")
            } else {
                errorMessage = "Failed to load receipts"
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error("[receipts] load error: \(error.localizedDescription)")
        }

        isLoading = false
    }
}

// MARK: - Receipt Row

struct ReceiptRow: View {
    let receipt: Receipt

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.displayVendor)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(receipt.displayDate)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let location = receipt.storeLocation, !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Text("\(receipt.itemCount) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.2f", receipt.total))
                    .font(.headline)
                Text("AED")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Receipt Detail View

struct ReceiptDetailView: View {
    let receipt: Receipt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                // Header Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(receipt.displayVendor)
                                .font(.title2)
                                .fontWeight(.semibold)

                            if let location = receipt.storeLocation, !location.isEmpty {
                                Text(location)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Text(receipt.displayDate)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text(String(format: "%.2f", receipt.total))
                                .font(.title)
                                .fontWeight(.bold)
                            Text("AED")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Items Section
                Section("Items (\(receipt.items.count))") {
                    ForEach(receipt.items) { item in
                        ReceiptItemRow(item: item)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Receipt Item Row

struct ReceiptItemRow: View {
    let item: ReceiptItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)

                HStack(spacing: 8) {
                    if !item.displayQty.isEmpty {
                        Text(item.displayQty)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let category = item.category, !category.isEmpty {
                        Text(category)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            Text(item.displayTotal)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ReceiptsView()
    }
}
