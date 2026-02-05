import SwiftUI
import Combine

struct FinanceActivityView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedTransaction: Transaction?
    @State private var selectedDateRange: DateRange = .last30Days
    @State private var customStartDate = Constants.Dubai.calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var showingDateRangePicker = false
    @State private var showingExport = false
    @State private var csvURL: URL?

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

    private var groupedTransactions: [(String, [Transaction])] {
        let grouped = Dictionary(grouping: filteredTransactions) { transaction -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: transaction.date)
        }

        return grouped.sorted { $0.key > $1.key }.map { (key, transactions) in
            let displayDate = formatSectionDate(key)
            return (displayDate, transactions.sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        List {
            // Freshness indicator
            Section {
                HStack(spacing: 6) {
                    if let freshness = viewModel.financeFreshness {
                        Circle()
                            .fill(freshness.isStale ? Color.nexusWarning : Color.nexusSuccess)
                            .frame(width: 6, height: 6)
                        Text(freshness.syncTimeLabel)
                            .font(.caption)
                            .foregroundColor(freshness.isStale ? .nexusWarning : .secondary)
                    } else if let lastUpdated = viewModel.lastUpdated,
                              Date().timeIntervalSince(lastUpdated) > 300 || viewModel.isOffline {
                        Circle()
                            .fill(viewModel.isOffline ? Color.nexusWarning : Color.nexusSuccess)
                            .frame(width: 6, height: 6)
                        Text("Updated \(lastUpdated, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if viewModel.isOffline {
                        Text("(Offline)")
                            .font(.caption)
                            .foregroundColor(.nexusWarning)
                    }
                    Spacer()
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            // Date range selector
            Section {
                Button(action: { showingDateRangePicker = true }) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.nexusFinance)
                        Text(selectedDateRange.displayName)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // Category filters
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

            // Transactions grouped by date
            ForEach(groupedTransactions, id: \.0) { dateString, transactions in
                Section(header: Text(dateString)) {
                    ForEach(transactions) { transaction in
                        Button(action: {
                            selectedTransaction = transaction
                        }) {
                            ActivityTransactionRow(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Empty state
            if filteredTransactions.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No transactions")
                            .font(.headline)
                        Text(searchText.isEmpty && selectedCategory == nil ?
                             "Transactions will appear here" :
                             "Try adjusting your filters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
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
        .sheet(isPresented: $showingExport) {
            if let url = csvURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func formatSectionDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }

    private func exportToCSV() {
        var csv = "Date,Time,Merchant,Amount,Currency,Category,Source,Notes\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for transaction in filteredTransactions {
            let date = dateFormatter.string(from: transaction.date)
            let time = timeFormatter.string(from: transaction.date)
            let merchant = escapeCSV(transaction.merchantName)
            let amount = String(format: "%.2f", transaction.amount)
            let currency = transaction.currency
            let category = escapeCSV(transaction.category ?? "")
            let source = transaction.source ?? "unknown"
            let notes = escapeCSV(transaction.notes ?? "")

            csv += "\(date),\(time),\(merchant),\(amount),\(currency),\(category),\(source),\(notes)\n"
        }

        let fileName = "nexus-transactions-\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none).replacingOccurrences(of: "/", with: "-")).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            csvURL = tempURL
            showingExport = true
        } catch {
            #if DEBUG
            print("Failed to write CSV: \(error)")
            #endif
        }
    }

    private func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}

// MARK: - Activity Transaction Row (with date/time and source badge)

struct ActivityTransactionRow: View {
    let transaction: Transaction

    private var formattedDateTime: String {
        if Constants.Dubai.isDateInToday(transaction.date) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = Constants.Dubai.timeZone
        return formatter.string(from: transaction.date)
    }

    private var hasValidDate: Bool {
        // Check if the date is not the default/epoch date
        transaction.date > Date(timeIntervalSince1970: 86400) // After Jan 2, 1970
    }

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: categoryIcon)
                    .foregroundColor(categoryColor)
                    .font(.system(size: 16))
            }

            // Transaction details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transaction.merchantName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    // Corrected badge
                    if transaction.hasCorrection {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundColor(.nexusWarning)
                            .font(.caption2)
                    }
                }

                HStack(spacing: 6) {
                    // Category
                    if let category = transaction.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Source badge
                    if let source = transaction.source {
                        SourceBadge(source: source)
                    }

                    Spacer()

                    // Time
                    if hasValidDate {
                        Text(formattedDateTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Unknown time")
                            .font(.caption)
                            .foregroundColor(.nexusWarning)
                    }
                }
            }

            Spacer()

            // Amount with currency
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTransactionAmount(transaction))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(transaction.amount < 0 ? .primary : .nexusSuccess)

                // Show original currency if different from default
                if transaction.currency != AppSettings.shared.defaultCurrency {
                    Text(transaction.currency)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transaction.merchantName), \(formatTransactionAmount(transaction))")
    }

    private var categoryIcon: String {
        guard let category = transaction.category else { return "circle" }
        switch category.lowercased() {
        case "grocery", "groceries": return "cart.fill"
        case "restaurant", "food": return "fork.knife"
        case "transport", "transportation": return "car.fill"
        case "utilities": return "house.fill"
        case "entertainment": return "tv.fill"
        case "health": return "heart.fill"
        case "shopping": return "bag.fill"
        case "transfer": return "arrow.left.arrow.right"
        case "income", "salary": return "banknote.fill"
        default: return "creditcard.fill"
        }
    }

    private var categoryColor: Color {
        guard let category = transaction.category else { return .gray }
        switch category.lowercased() {
        case "grocery", "groceries": return .nexusWeight
        case "restaurant", "food": return .nexusFood
        case "transport", "transportation": return .nexusWater
        case "utilities": return .nexusMood
        case "entertainment": return .nexusPrimaryLight
        case "health": return .nexusProtein
        case "shopping": return .nexusPrimary
        case "transfer": return .gray
        case "income", "salary": return .nexusSuccess
        default: return .nexusFinance
        }
    }

    private func formatTransactionAmount(_ transaction: Transaction) -> String {
        let formatted = formatCurrency(abs(transaction.amount), currency: transaction.currency)
        if transaction.amount > 0 {
            return "+\(formatted)"
        }
        return "-\(formatted)"
    }
}

// MARK: - Source Badge

struct SourceBadge: View {
    let source: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: sourceIcon)
                .font(.system(size: 8))
            Text(sourceLabel)
                .font(.system(size: 9))
        }
        .foregroundColor(sourceColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(sourceColor.opacity(0.15))
        .cornerRadius(4)
    }

    private var sourceIcon: String {
        switch source.lowercased() {
        case "sms": return "message.fill"
        case "manual": return "hand.draw.fill"
        case "receipt": return "doc.text.fill"
        case "import": return "square.and.arrow.down.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var sourceLabel: String {
        switch source.lowercased() {
        case "sms": return "SMS"
        case "manual": return "Manual"
        case "receipt": return "Receipt"
        case "import": return "Import"
        default: return source.capitalized
        }
    }

    private var sourceColor: Color {
        switch source.lowercased() {
        case "sms": return .nexusWater
        case "manual": return .nexusMood
        case "receipt": return .nexusFood
        case "import": return .nexusSuccess
        default: return .gray
        }
    }
}
