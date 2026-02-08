import SwiftUI
import Combine
import os

private let logger = Logger(subsystem: "com.nexus", category: "FinanceActivity")

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
    @State private var transactionToDelete: Transaction?
    @State private var showingDeleteConfirmation = false
    @State private var groupingMode: GroupingMode = .byDay

    enum GroupingMode: String, CaseIterable {
        case byDay = "Day"
        case byWeek = "Week"
        case byCategory = "Category"

        var icon: String {
            switch self {
            case .byDay: return "calendar"
            case .byWeek: return "calendar.badge.clock"
            case .byCategory: return "folder"
            }
        }
    }

    // MARK: - Sync Status Helpers

    private var syncStatusColor: Color {
        if viewModel.isOffline {
            return NexusTheme.Colors.Semantic.amber
        } else if viewModel.isLoading {
            return NexusTheme.Colors.Semantic.blue
        } else if let freshness = viewModel.financeFreshness, freshness.isStale {
            return NexusTheme.Colors.Semantic.amber
        } else {
            return NexusTheme.Colors.Semantic.green
        }
    }

    private var syncStatusIcon: String {
        if viewModel.isOffline {
            return "wifi.slash"
        } else if viewModel.isLoading {
            return "arrow.triangle.2.circlepath"
        } else if let freshness = viewModel.financeFreshness, freshness.isStale {
            return "clock"
        } else {
            return "checkmark.circle"
        }
    }

    private var syncStatusTitle: String {
        if viewModel.isOffline {
            return "Offline Mode"
        } else if viewModel.isLoading {
            return "Syncing..."
        } else {
            return "Transactions"
        }
    }

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
        switch groupingMode {
        case .byDay:
            let grouped = Dictionary(grouping: filteredTransactions) { transaction -> String in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: transaction.date)
            }
            return grouped.sorted { $0.key > $1.key }.map { (key, transactions) in
                let displayDate = formatSectionDate(key)
                return (displayDate, transactions.sorted { $0.date > $1.date })
            }

        case .byWeek:
            let grouped = Dictionary(grouping: filteredTransactions) { transaction -> String in
                let calendar = Calendar.current
                let weekOfYear = calendar.component(.weekOfYear, from: transaction.date)
                let year = calendar.component(.yearForWeekOfYear, from: transaction.date)
                return "\(year)-W\(String(format: "%02d", weekOfYear))"
            }
            return grouped.sorted { $0.key > $1.key }.map { (key, transactions) in
                let displayWeek = formatWeekLabel(key)
                return (displayWeek, transactions.sorted { $0.date > $1.date })
            }

        case .byCategory:
            let grouped = Dictionary(grouping: filteredTransactions) { transaction -> String in
                transaction.category ?? "Uncategorized"
            }
            return grouped.sorted { $0.key < $1.key }.map { (category, transactions) in
                let total = transactions.reduce(0) { $0 + abs($1.amount) }
                let displayCategory = "\(category.capitalized) (\(formatCurrency(total, currency: AppSettings.shared.defaultCurrency)))"
                return (displayCategory, transactions.sorted { $0.date > $1.date })
            }
        }
    }

    private func formatWeekLabel(_ weekKey: String) -> String {
        // Parse "2024-W05" format
        let parts = weekKey.split(separator: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else { return weekKey }

        let calendar = Calendar.current
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = calendar.firstWeekday

        guard let weekStart = calendar.date(from: components) else { return weekKey }
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        if calendar.component(.month, from: weekStart) == calendar.component(.month, from: weekEnd) {
            // Same month: "Jan 1-7"
            let endDay = DateFormatter()
            endDay.dateFormat = "d"
            return "\(formatter.string(from: weekStart))-\(endDay.string(from: weekEnd))"
        } else {
            // Different months: "Jan 28 - Feb 3"
            return "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
        }
    }

    var body: some View {
        List {
            // Sync status indicator
            Section {
                HStack(spacing: 10) {
                    // Status icon
                    ZStack {
                        Circle()
                            .fill(syncStatusColor.opacity(0.15))
                            .frame(width: 28, height: 28)

                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: syncStatusIcon)
                                .font(.caption)
                                .foregroundColor(syncStatusColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(syncStatusTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(viewModel.isOffline ? NexusTheme.Colors.Semantic.amber : .primary)

                        if let freshness = viewModel.financeFreshness {
                            Text(freshness.syncTimeLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let lastUpdated = viewModel.lastUpdated {
                            Text("Updated \(lastUpdated, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Queued items badge
                    if viewModel.queuedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                                .font(.caption)
                            Text("\(viewModel.queuedCount) pending")
                                .font(.caption)
                        }
                        .foregroundColor(NexusTheme.Colors.Semantic.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(NexusTheme.Colors.Semantic.blue.opacity(0.12))
                        .cornerRadius(NexusTheme.Radius.xs)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(viewModel.isOffline ? NexusTheme.Colors.Semantic.amber.opacity(0.08) : Color.clear)

            // Date range and grouping controls
            Section {
                HStack(spacing: 16) {
                    // Date range button
                    Button(action: { showingDateRangePicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .foregroundColor(NexusTheme.Colors.Semantic.green)
                                .font(.subheadline)
                            Text(selectedDateRange.displayName)
                                .font(.subheadline)
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(NexusTheme.Colors.cardAlt)
                        .cornerRadius(NexusTheme.Radius.sm)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Grouping mode picker
                    Menu {
                        ForEach(GroupingMode.allCases, id: \.self) { mode in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    groupingMode = mode
                                }
                            } label: {
                                Label(mode.rawValue, systemImage: mode.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: groupingMode.icon)
                                .foregroundColor(NexusTheme.Colors.accent)
                                .font(.subheadline)
                            Text("Group: \(groupingMode.rawValue)")
                                .font(.subheadline)
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(NexusTheme.Colors.cardAlt)
                        .cornerRadius(NexusTheme.Radius.sm)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

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

            // Transaction summary header
            if !filteredTransactions.isEmpty {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(filteredTransactions.count) transactions")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(selectedDateRange.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            let totalSpent = filteredTransactions.filter { $0.amount < 0 }.reduce(0) { $0 + abs($1.amount) }
                            Text(formatCurrency(totalSpent, currency: AppSettings.shared.defaultCurrency))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(NexusTheme.Colors.Semantic.red)
                            Text("total spent")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(NexusTheme.Colors.card)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                transactionToDelete = transaction
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                selectedTransaction = transaction
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(NexusTheme.Colors.Semantic.blue)
                        }
                    }
                }
            }

            // Empty state
            if filteredTransactions.isEmpty {
                Section {
                    ThemeEmptyState(
                        icon: "tray",
                        headline: "No Transactions",
                        description: searchText.isEmpty && selectedCategory == nil
                            ? "Transactions will appear here once recorded."
                            : "Try adjusting your filters."
                    )
                }
                .listRowBackground(Color.clear)
            }

            // Pagination - manual button only (no auto-load on appear)
            if viewModel.hasMoreTransactions && !filteredTransactions.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .accessibilityLabel("Loading more transactions")
                        } else {
                            Button("Load More") {
                                Task {
                                    await viewModel.loadMoreTransactions()
                                }
                            }
                            .accessibilityLabel("Load more transactions")
                            .accessibilityHint("Double tap to load additional transactions")
                        }
                        Spacer()
                    }
                    .frame(minHeight: 44)
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
        .alert("Delete Transaction", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                transactionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let transaction = transactionToDelete, let id = transaction.id {
                    Task {
                        await viewModel.deleteTransaction(id: id)
                    }
                }
                transactionToDelete = nil
            }
        } message: {
            if let transaction = transactionToDelete {
                Text("Are you sure you want to delete \"\(transaction.merchantName)\" for \(formatCurrency(abs(transaction.amount), currency: transaction.currency))?")
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
            logger.error("Failed to write CSV: \(error.localizedDescription)")
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
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
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
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
                    }
                }
            }

            Spacer()

            // Amount with currency
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTransactionAmount(transaction))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(transaction.amount < 0 ? .primary : NexusTheme.Colors.Semantic.green)

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
        case "grocery", "groceries": return NexusTheme.Colors.Semantic.purple
        case "restaurant", "food": return NexusTheme.Colors.Semantic.amber
        case "transport", "transportation": return NexusTheme.Colors.Semantic.blue
        case "utilities": return NexusTheme.Colors.accent
        case "entertainment": return NexusTheme.Colors.accent
        case "health": return NexusTheme.Colors.Semantic.red
        case "shopping": return NexusTheme.Colors.accent
        case "transfer": return .gray
        case "income", "salary": return NexusTheme.Colors.Semantic.green
        default: return NexusTheme.Colors.Semantic.green
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
        case "sms": return NexusTheme.Colors.Semantic.blue
        case "manual": return NexusTheme.Colors.accent
        case "receipt": return NexusTheme.Colors.Semantic.amber
        case "import": return NexusTheme.Colors.Semantic.green
        default: return .gray
        }
    }
}
