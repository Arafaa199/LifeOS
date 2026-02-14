import SwiftUI

struct ReceiptsListView: View {
    @ObservedObject var viewModel: ReceiptsViewModel
    @State private var selectedReceipt: ReceiptSummary?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.receipts.isEmpty {
                ThemeLoadingView(message: "Loading receipts...")
            } else if viewModel.receipts.isEmpty {
                emptyState
            } else {
                receiptList
            }
        }
        .sheet(item: $selectedReceipt) { receipt in
            NavigationView {
                ReceiptDetailView(viewModel: viewModel, receiptId: receipt.id)
            }
        }
        .refreshable {
            await viewModel.loadReceipts()
        }
        .task {
            if viewModel.receipts.isEmpty {
                await viewModel.loadReceipts()
            }
        }
    }

    private var emptyState: some View {
        ThemeEmptyState(
            icon: "receipt",
            headline: "No Receipts Yet",
            description: "Your grocery receipts will appear here. Link items to foods for nutrition tracking."
        )
    }

    private var receiptList: some View {
        List {
            if let error = viewModel.errorMessage, !error.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
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
                }
            }

            ForEach(viewModel.receiptsByMonth, id: \.0) { monthKey, receipts in
                Section(viewModel.formatMonthHeader(monthKey)) {
                    ForEach(receipts) { receipt in
                        ReceiptSummaryRow(receipt: receipt)
                            .onTapGesture { selectedReceipt = receipt }
                    }
                }
            }

            // Pagination trigger — load more when section appears
            if viewModel.hasMoreReceipts {
                Section {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Button("Load More") {
                                Task {
                                    await viewModel.loadMoreReceipts()
                                }
                            }
                        }
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
                .onAppear {
                    Task {
                        await viewModel.loadMoreReceipts()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NexusTheme.Colors.background)
    }
}

struct ReceiptSummaryRow: View {
    let receipt: ReceiptSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "receipt")
                .font(.title3)
                .foregroundColor(NexusTheme.Colors.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.store_name ?? receipt.vendor)
                    .font(.body)
                    .fontWeight(.medium)

                Text(formatDate(receipt.receipt_date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatAmount(receipt.total_amount, currency: receipt.currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                MatchBadge(matched: receipt.matched_count, total: receipt.item_count)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(receipt.store_name ?? receipt.vendor), \(formatDate(receipt.receipt_date)), \(formatAmount(receipt.total_amount, currency: receipt.currency))")
    }

    private func formatDate(_ dateStr: String) -> String {
        // Handle both "yyyy-MM-dd" and ISO8601 "yyyy-MM-ddTHH:mm:ss.SSSZ"
        let dateOnly = String(dateStr.prefix(10))
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: dateOnly) else { return dateOnly }
        let output = DateFormatter()
        output.dateStyle = .medium
        return output.string(from: date)
    }

    private func formatAmount(_ amount: Double, currency: String) -> String {
        if currency == "AED" {
            return String(format: "%.2f AED", amount)
        }
        return String(format: "%.2f %@", amount, currency)
    }
}

struct MatchBadge: View {
    let matched: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            if matched > 0 {
                Image(systemName: "leaf.fill")
                    .font(.caption2)
                    .foregroundColor(NexusTheme.Colors.Semantic.amber)
            }
            Text("\(matched)/\(total)")
                .font(.caption)
                .foregroundColor(matched > 0 ? NexusTheme.Colors.Semantic.amber : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(matched > 0 ? NexusTheme.Colors.Semantic.amber.opacity(0.15) : Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}
