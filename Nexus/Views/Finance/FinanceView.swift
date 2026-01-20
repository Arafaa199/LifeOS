import SwiftUI

struct FinanceView: View {
    @StateObject private var viewModel = FinanceViewModel()
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom Tab Picker
                Picker("Finance Tab", selection: $selectedTab) {
                    Text("Quick").tag(0)
                    Text("Transactions").tag(1)
                    Text("Budget").tag(2)
                    Text("Insights").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()

                // Tab Content
                TabView(selection: $selectedTab) {
                    QuickExpenseView(viewModel: viewModel)
                        .tag(0)

                    TransactionsListView(viewModel: viewModel)
                        .tag(1)

                    BudgetView(viewModel: viewModel)
                        .tag(2)

                    InsightsView(viewModel: viewModel)
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Finance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.triggerSMSImport()
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
    }
}

// MARK: - Quick Expense View

struct QuickExpenseView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var expenseText = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false

    private var overBudgetCategories: [Budget] {
        viewModel.summary.budgets.filter { budget in
            guard let spent = budget.spent else { return false }
            return spent > budget.budgetAmount
        }
    }

    private var nearBudgetCategories: [Budget] {
        viewModel.summary.budgets.filter { budget in
            guard let spent = budget.spent else { return false }
            let percentage = spent / budget.budgetAmount
            return percentage >= 0.8 && percentage <= 1.0
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Budget Alerts
                if !overBudgetCategories.isEmpty {
                    budgetAlertBanner(categories: overBudgetCategories, isOverBudget: true)
                } else if !nearBudgetCategories.isEmpty {
                    budgetAlertBanner(categories: nearBudgetCategories, isOverBudget: false)
                }

                // Today's Spending Summary
                summaryCard

                // Quick Log Input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Expense")
                        .font(.headline)

                    VStack(spacing: 12) {
                        TextField("e.g., $45 at Whole Foods", text: $expenseText)
                            .textFieldStyle(.roundedBorder)
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                submitExpense()
                            }

                        Text("Try: \"$45 groceries at Whole Foods\" or \"spent $12 on coffee\"")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: submitExpense) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Log Expense")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(expenseText.isEmpty || viewModel.isLoading)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)

                // Category Quick Actions
                categoryQuickActions

                // Manual Entry Buttons
                HStack(spacing: 12) {
                    Button(action: {
                        showingAddExpense = true
                    }) {
                        HStack {
                            Image(systemName: "minus.circle.fill")
                            Text("Add Expense")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Button(action: {
                        showingAddIncome = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Income")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }

                // Recent Transactions
                if !viewModel.recentTransactions.isEmpty {
                    recentTransactionsSection
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddIncome) {
            IncomeView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.loadFinanceSummary()
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Today's Spending")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(viewModel.summary.formatAmount(viewModel.summary.totalSpent))
                        .font(.system(size: 32, weight: .bold))
                }
                Spacer()
            }

            HStack(spacing: 20) {
                StatItem(
                    icon: "cart.fill",
                    label: "Grocery",
                    value: viewModel.summary.formatAmount(viewModel.summary.grocerySpent),
                    color: .green
                )

                StatItem(
                    icon: "fork.knife",
                    label: "Eating Out",
                    value: viewModel.summary.formatAmount(viewModel.summary.eatingOutSpent),
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var categoryQuickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Categories")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ExpenseCategory.allCases, id: \.self) { category in
                    Button(action: {
                        expenseText = category.rawValue
                        isTextFieldFocused = true
                    }) {
                        HStack {
                            Image(systemName: category.icon)
                            Text(category.rawValue)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.headline)

            ForEach(viewModel.recentTransactions.prefix(5)) { transaction in
                TransactionRow(transaction: transaction)
            }
        }
    }

    private func submitExpense() {
        Task {
            await viewModel.logExpense(expenseText)
            expenseText = ""
            isTextFieldFocused = false
        }
    }

    @ViewBuilder
    private func budgetAlertBanner(categories: [Budget], isOverBudget: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isOverBudget ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundColor(isOverBudget ? .red : .orange)
                Text(isOverBudget ? "Over Budget" : "Budget Warning")
                    .font(.headline)
                    .foregroundColor(isOverBudget ? .red : .orange)
                Spacer()
            }

            ForEach(categories) { budget in
                HStack {
                    Text(budget.category.capitalized)
                        .font(.subheadline)
                    Spacer()
                    if let spent = budget.spent {
                        if isOverBudget {
                            Text(String(format: "AED %.0f over", spent - budget.budgetAmount))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        } else {
                            let percentage = (spent / budget.budgetAmount) * 100
                            Text(String(format: "%.0f%% used", percentage))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .foregroundColor(isOverBudget ? .red : .orange)
            }
        }
        .padding()
        .background(isOverBudget ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Transactions List View

struct TransactionsListView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingShareSheet = false
    @State private var csvURL: URL?
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var showingFilters = false
    @State private var selectedTransaction: Transaction?
    @State private var selectedDateRange: DateRange = .last30Days
    @State private var customStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
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
            print("Failed to write CSV: \(error)")
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

// MARK: - Budget View

struct BudgetView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingBudgetSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.summary.budgets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No budgets set")
                            .font(.headline)
                        Text("Set monthly budgets to track spending")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button(action: {
                            showingBudgetSettings = true
                        }) {
                            Text("Set Budgets")
                                .fontWeight(.semibold)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.top)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    ForEach(viewModel.summary.budgets) { budget in
                        BudgetCard(budget: budget)
                    }
                }

                // Spending Charts
                if !viewModel.summary.categoryBreakdown.isEmpty {
                    SpendingChartsView(
                        categoryBreakdown: viewModel.summary.categoryBreakdown,
                        totalSpent: viewModel.summary.totalSpent
                    )
                }

                // Category Breakdown (Text List)
                if !viewModel.summary.categoryBreakdown.isEmpty {
                    categoryBreakdownSection
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingBudgetSettings) {
            BudgetSettingsView()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !viewModel.summary.budgets.isEmpty {
                    Button("Manage") {
                        showingBudgetSettings = true
                    }
                }
            }
        }
    }

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Month by Category")
                .font(.headline)

            ForEach(Array(viewModel.summary.categoryBreakdown.sorted(by: { $0.value > $1.value })), id: \.key) { category, amount in
                HStack {
                    Text(category.capitalized)
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "$%.2f", amount))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Supporting Views

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchantName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let category = transaction.category {
                    Text(category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(transaction.displayAmount)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(transaction.amount < 0 ? .red : .green)
        }
        .padding(.vertical, 4)
    }
}

struct BudgetCard: View {
    let budget: Budget

    private var progress: Double {
        guard let spent = budget.spent else { return 0 }
        return min(spent / budget.budgetAmount, 1.0)
    }

    private var isOverBudget: Bool {
        guard let spent = budget.spent else { return false }
        return spent > budget.budgetAmount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(budget.category.capitalized)
                    .font(.headline)
                Spacer()
                Text(String(format: "$%.0f / $%.0f", budget.spent ?? 0, budget.budgetAmount))
                    .font(.subheadline)
                    .foregroundColor(isOverBudget ? .red : .secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.tertiarySystemBackground))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(isOverBudget ? Color.red : Color.green)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)

            if let remaining = budget.remaining {
                Text(remaining >= 0 ? String(format: "$%.2f remaining", remaining) : String(format: "$%.2f over budget", abs(remaining)))
                    .font(.caption)
                    .foregroundColor(remaining >= 0 ? .secondary : .red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

#Preview {
    FinanceView()
}
