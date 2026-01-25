import SwiftUI

struct TransactionsListView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingShareSheet = false
    @State private var csvURL: URL?
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var showingFilters = false
    @State private var selectedTransaction: Transaction?
    @State private var selectedDateRange: DateRange = .last30Days
    @State private var customStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var showingDateRangePicker = false

    private var filteredTransactions: [Transaction] {
        let dateRange = selectedDateRange == .custom ?
            (start: customStartDate, end: customEndDate) :
            selectedDateRange.getDateRange()

        return viewModel.recentTransactions.compactMap { transaction -> Transaction? in
            // Date range filter
            guard transaction.date >= dateRange.start && transaction.date < dateRange.end else {
                return nil
            }

            // Search filter
            if !searchText.isEmpty {
                let matchesMerchant = transaction.merchantName.localizedCaseInsensitiveContains(searchText)
                let matchesCategory = transaction.category?.localizedCaseInsensitiveContains(searchText) ?? false
                let matchesNotes = transaction.notes?.localizedCaseInsensitiveContains(searchText) ?? false

                guard matchesMerchant || matchesCategory || matchesNotes else {
                    return nil
                }
            }

            // Category filter
            if let category = selectedCategory {
                guard transaction.category == category else {
                    return nil
                }
            }

            return transaction
        }
    }

    private var categories: [String] {
        let allCategories = viewModel.recentTransactions.compactMap { $0.category }
        return Array(Set(allCategories)).sorted()
    }

    var body: some View {
        List {
            // Date range selector
            Section {
                Button(action: { showingDateRangePicker = true }) {
                    HStack {
                        Image(systemName: "calendar")
                        Text(selectedDateRange.displayName)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if !categories.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(
                                title: "All",
                                isSelected: selectedCategory == nil,
                                action: { selectedCategory = nil }
                            )

                            ForEach(categories, id: \.self) { category in
                                FilterChip(
                                    title: category,
                                    isSelected: selectedCategory == category,
                                    action: {
                                        selectedCategory = selectedCategory == category ? nil : category
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(filteredTransactions) { transaction in
                    Button(action: {
                        selectedTransaction = transaction
                    }) {
                        TransactionRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                if !searchText.isEmpty || selectedCategory != nil {
                    Text("\(filteredTransactions.count) transaction(s)")
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search transactions")
        .refreshable {
            await viewModel.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportToCSV) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.recentTransactions.isEmpty)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = csvURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailView(viewModel: viewModel, transaction: transaction)
        }
        .sheet(isPresented: $showingDateRangePicker) {
            DateRangeFilterView(
                selectedRange: $selectedDateRange,
                customStartDate: $customStartDate,
                customEndDate: $customEndDate,
                isPresented: $showingDateRangePicker
            )
        }
    }

    private func exportToCSV() {
        let csv = generateCSV()
        let fileName = "nexus-transactions-\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            csvURL = tempURL
            showingShareSheet = true
        } catch {
            #if DEBUG
            print("Failed to write CSV: \(error)")
            #endif
        }
    }

    private func generateCSV() -> String {
        var csv = "Date,Merchant,Amount,Currency,Category,Subcategory,Notes\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for transaction in viewModel.recentTransactions {
            let date = dateFormatter.string(from: transaction.date)
            let merchant = escapeCSV(transaction.merchantName)
            let amount = String(format: "%.2f", abs(transaction.amount))
            let currency = transaction.currency
            let category = escapeCSV(transaction.category ?? "")
            let subcategory = escapeCSV(transaction.subcategory ?? "")
            let notes = escapeCSV(transaction.notes ?? "")

            csv += "\(date),\(merchant),\(amount),\(currency),\(category),\(subcategory),\(notes)\n"
        }

        return csv
    }

    private func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}
