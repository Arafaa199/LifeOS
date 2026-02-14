import SwiftUI
import Combine

struct FinancePlanningView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = FinancePlanningViewModel()
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var selectedSection = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedSection) {
                    Text("Categories").tag(0)
                    Text("Recurring").tag(1)
                    Text("Rules").tag(2)
                    Text("Settings").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()

                TabView(selection: $selectedSection) {
                    CategoriesListView(viewModel: viewModel)
                        .tag(0)

                    RecurringItemsListView(viewModel: viewModel)
                        .tag(1)

                    MatchingRulesListView(viewModel: viewModel)
                        .tag(2)

                    FinanceSettingsView()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Finance Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                viewModel.loadAll()
            }
        }
    }
}

// MARK: - Finance Settings View (Currency & Preferences)

struct FinanceSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        List {
            Section("Currency") {
                Picker("Default Currency", selection: $settings.defaultCurrency) {
                    ForEach(AppSettings.supportedCurrencies, id: \.self) { currency in
                        Text(currency).tag(currency)
                    }
                }

                Toggle("Show Currency Conversion", isOn: $settings.showCurrencyConversion)

                Text("Conversion is currently disabled. All amounts will display in their original currency.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Display") {
                Text("Currency formatting uses locale settings. AED amounts use \"AED\" prefix instead of symbols.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Data Sources") {
                NavigationLink(destination: ReceiptsListView(viewModel: ReceiptsViewModel())) {
                    HStack {
                        Image(systemName: "receipt")
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                            .frame(width: 24)
                        Text("Receipts")
                        Spacer()
                        Text("From email")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink(destination: InstallmentsView(viewModel: FinanceViewModel())) {
                    HStack {
                        Image(systemName: "creditcard.and.123")
                            .foregroundColor(NexusTheme.Colors.accent)
                            .frame(width: 24)
                        Text("Installments")
                        Spacer()
                        Text("BNPL tracking")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink(destination: SubscriptionsView()) {
                    HStack {
                        Image(systemName: "repeat")
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                            .frame(width: 24)
                        Text("Subscriptions")
                        Spacer()
                        Text("Monthly bills")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NexusTheme.Colors.background)
    }
}

// MARK: - View Model

@MainActor
class FinancePlanningViewModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var recurringItems: [RecurringItem] = []
    @Published var matchingRules: [MatchingRule] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = NexusAPI.shared

    func loadAll() {
        Task {
            await loadCategories()
            await loadRecurringItems()
            await loadMatchingRules()
        }
    }

    func loadCategories() async {
        isLoading = true
        do {
            let response = try await api.fetchCategories()
            if response.success, let data = response.data {
                categories = data.sorted { $0.displayOrder < $1.displayOrder }
            }
        } catch {
            errorMessage = "Failed to load categories: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadRecurringItems() async {
        isLoading = true
        do {
            let response = try await api.fetchRecurringItems()
            if response.success, let data = response.data {
                recurringItems = data.filter { $0.isActive }
            }
        } catch {
            errorMessage = "Failed to load recurring items: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadMatchingRules() async {
        isLoading = true
        do {
            let response = try await api.fetchMatchingRules()
            if response.success, let data = response.data {
                matchingRules = data.filter { $0.isActive }.sorted { $0.priority > $1.priority }
            }
        } catch {
            errorMessage = "Failed to load rules: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func createCategory(_ request: CreateCategoryRequest) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.createCategory(request)
            if response.success {
                await loadCategories()
                return true
            } else {
                errorMessage = response.message ?? "Failed to create category"
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteCategory(id: Int) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.deleteCategory(id: id)
            if response.success {
                await loadCategories()
                return true
            } else {
                errorMessage = response.message ?? "Failed to delete category"
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createRecurringItem(_ request: CreateRecurringItemRequest) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.createRecurringItem(request)
            if response.success {
                await loadRecurringItems()
                return true
            } else {
                errorMessage = response.message ?? "Failed to create recurring item"
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteRecurringItem(id: Int) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.deleteRecurringItem(id: id)
            if response.success {
                await loadRecurringItems()
                return true
            } else {
                errorMessage = response.message ?? "Failed to delete recurring item"
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createMatchingRule(_ request: CreateMatchingRuleRequest) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.createMatchingRule(request)
            if response.success {
                await loadMatchingRules()
                return true
            } else {
                errorMessage = response.message ?? "Failed to create rule"
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteMatchingRule(id: Int) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.deleteMatchingRule(id: id)
            if response.success {
                await loadMatchingRules()
                return true
            } else {
                errorMessage = response.message ?? "Failed to delete rule"
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - Categories List

struct CategoriesListView: View {
    @ObservedObject var viewModel: FinancePlanningViewModel
    @State private var showingAddCategory = false

    var body: some View {
        List {
            Section("Expense Categories") {
                ForEach(viewModel.categories.filter { $0.isExpense }) { category in
                    CategoryRow(category: category)
                }
                .onDelete { offsets in
                    deleteCategories(at: offsets, from: viewModel.categories.filter { $0.isExpense })
                }
            }

            Section("Income Categories") {
                ForEach(viewModel.categories.filter { $0.isIncome }) { category in
                    CategoryRow(category: category)
                }
                .onDelete { offsets in
                    deleteCategories(at: offsets, from: viewModel.categories.filter { $0.isIncome })
                }
            }
        }
        .overlay {
            if viewModel.categories.isEmpty && !viewModel.isLoading {
                emptyState
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddCategory = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategoryView(viewModel: viewModel)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Categories")
                .font(.headline)
            Text("Categories are used to organize your transactions")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func deleteCategories(at offsets: IndexSet, from filtered: [Category]) {
        for offset in offsets {
            let category = filtered[offset]
            Task {
                await viewModel.deleteCategory(id: category.id)
            }
        }
    }
}

struct CategoryRow: View {
    let category: Category

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.displayIcon)
                .font(.title2)
                .foregroundColor(category.isExpense ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.Semantic.green)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.body)
                if let keywords = category.keywords, !keywords.isEmpty {
                    Text(keywords.prefix(3).joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !category.isActive {
                Text("Inactive")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Category

struct AddCategoryView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinancePlanningViewModel

    @State private var name = ""
    @State private var type = "expense"
    @State private var icon = "folder.fill"
    @State private var keywords = ""
    @State private var isSubmitting = false

    private let iconOptions = [
        "cart.fill", "fork.knife", "car.fill", "bolt.fill",
        "tv.fill", "heart.fill", "bag.fill", "house.fill",
        "creditcard.fill", "briefcase.fill", "gift.fill", "banknote"
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Category Details") {
                    TextField("Name", text: $name)

                    Picker("Type", selection: $type) {
                        Text("Expense").tag("expense")
                        Text("Income").tag("income")
                    }
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(iconOptions, id: \.self) { iconName in
                            Button(action: { icon = iconName }) {
                                Image(systemName: iconName)
                                    .font(.title2)
                                    .foregroundColor(icon == iconName ? .white : .primary)
                                    .frame(width: 44, height: 44)
                                    .background(icon == iconName ? NexusTheme.Colors.accent : NexusTheme.Colors.cardAlt)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Keywords (comma separated)") {
                    TextField("e.g., walmart, target, costco", text: $keywords)
                        .autocapitalization(.none)
                }

                Section {
                    Button(action: saveCategory) {
                        if isSubmitting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Text("Saving...")
                                Spacer()
                            }
                        } else {
                            Text("Add Category")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(name.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Add Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func saveCategory() {
        guard !isSubmitting else { return }
        isSubmitting = true

        let keywordArray = keywords.isEmpty ? nil : keywords.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

        Task {
            let request = CreateCategoryRequest(
                name: name,
                type: type,
                icon: icon,
                color: nil,
                keywords: keywordArray,
                displayOrder: nil
            )
            let success = await viewModel.createCategory(request)
            if success {
                dismiss()
            } else {
                isSubmitting = false
            }
        }
    }
}

// MARK: - Recurring Items List

struct RecurringItemsListView: View {
    @ObservedObject var viewModel: FinancePlanningViewModel
    @State private var showingAddItem = false

    var body: some View {
        List {
            // Subscriptions shortcut
            Section {
                NavigationLink(destination: SubscriptionsView()) {
                    HStack {
                        Image(systemName: "repeat.circle.fill")
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                        Text("View Subscriptions")
                        Spacer()
                        Text("\(viewModel.recurringItems.filter { $0.isExpense && $0.cadence == "monthly" }.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Recurring Expenses") {
                ForEach(viewModel.recurringItems.filter { $0.isExpense }) { item in
                    RecurringItemRow(item: item)
                }
                .onDelete { offsets in
                    deleteItems(at: offsets, from: viewModel.recurringItems.filter { $0.isExpense })
                }
            }

            Section("Recurring Income") {
                ForEach(viewModel.recurringItems.filter { $0.isIncome }) { item in
                    RecurringItemRow(item: item)
                }
                .onDelete { offsets in
                    deleteItems(at: offsets, from: viewModel.recurringItems.filter { $0.isIncome })
                }
            }
        }
        .overlay {
            if viewModel.recurringItems.isEmpty && !viewModel.isLoading {
                emptyState
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddItem = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddRecurringItemView(viewModel: viewModel)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "repeat.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Recurring Items")
                .font(.headline)
            Text("Track your recurring bills and income")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func deleteItems(at offsets: IndexSet, from filtered: [RecurringItem]) {
        for offset in offsets {
            let item = filtered[offset]
            Task {
                await viewModel.deleteRecurringItem(id: item.id)
            }
        }
    }
}

// MARK: - Add Recurring Item

struct AddRecurringItemView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinancePlanningViewModel

    @State private var name = ""
    @State private var amount = ""
    @State private var type = "expense"
    @State private var cadence = "monthly"
    @State private var dayOfMonth = 1
    @State private var isSubmitting = false

    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Name (e.g., Rent, Netflix)", text: $name)

                    HStack {
                        Text("AED")
                            .foregroundColor(.secondary)
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }

                    Picker("Type", selection: $type) {
                        Text("Expense").tag("expense")
                        Text("Income").tag("income")
                    }
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $cadence) {
                        Text("Monthly").tag("monthly")
                        Text("Weekly").tag("weekly")
                        Text("Every 2 Weeks").tag("biweekly")
                        Text("Quarterly").tag("quarterly")
                        Text("Yearly").tag("yearly")
                    }

                    if cadence == "monthly" {
                        Picker("Day of Month", selection: $dayOfMonth) {
                            ForEach(1...28, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                    }
                }

                Section {
                    Button(action: saveItem) {
                        if isSubmitting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Text("Saving...")
                                Spacer()
                            }
                        } else {
                            Text("Add Recurring Item")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(name.isEmpty || amount.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Add Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func saveItem() {
        guard !isSubmitting, let amountValue = Double(amount) else { return }
        isSubmitting = true

        Task {
            let request = CreateRecurringItemRequest(
                name: name,
                amount: amountValue,
                currency: "AED",
                type: type,
                cadence: cadence,
                dayOfMonth: cadence == "monthly" ? dayOfMonth : nil,
                dayOfWeek: nil,
                nextDueDate: nil,
                categoryId: nil,
                merchantPattern: nil,
                autoCreate: false,
                notes: nil
            )
            let success = await viewModel.createRecurringItem(request)
            if success {
                dismiss()
            } else {
                isSubmitting = false
            }
        }
    }
}

// MARK: - Matching Rules List

struct MatchingRulesListView: View {
    @ObservedObject var viewModel: FinancePlanningViewModel
    @State private var showingAddRule = false

    var body: some View {
        List {
            ForEach(viewModel.matchingRules) { rule in
                MatchingRuleRow(rule: rule)
            }
            .onDelete(perform: deleteRules)
        }
        .overlay {
            if viewModel.matchingRules.isEmpty && !viewModel.isLoading {
                emptyState
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddRule = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRule) {
            AddMatchingRuleView(viewModel: viewModel)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Matching Rules")
                .font(.headline)
            Text("Rules auto-categorize transactions by merchant")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        for offset in offsets {
            let rule = viewModel.matchingRules[offset]
            Task {
                await viewModel.deleteMatchingRule(id: rule.id)
            }
        }
    }
}

struct MatchingRuleRow: View {
    let rule: MatchingRule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rule.merchantPattern)
                    .font(.body)
                    .fontWeight(.medium)

                Spacer()

                Text("P\(rule.priority)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(NexusTheme.Colors.accent.opacity(0.1))
                    .foregroundColor(NexusTheme.Colors.accent)
                    .cornerRadius(4)
            }

            HStack(spacing: 8) {
                if let category = rule.category {
                    Label(category, systemImage: "folder.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(rule.confidenceDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if rule.hasMatches {
                    Text("\(rule.matchCount) matches")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Matching Rule

struct AddMatchingRuleView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinancePlanningViewModel

    @State private var pattern = ""
    @State private var selectedCategory: ExpenseCategory = .other
    @State private var priority = 50
    @State private var confidence = 100
    @State private var isSubmitting = false

    var body: some View {
        NavigationView {
            Form {
                Section("Pattern") {
                    TextField("Merchant pattern (e.g., %CARREFOUR%)", text: $pattern)
                        .autocapitalization(.none)
                    Text("Use % as wildcard. Example: %UBER% matches any transaction with UBER")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue)
                            }
                            .tag(category)
                        }
                    }
                }

                Section("Priority & Confidence") {
                    Stepper("Priority: \(priority)", value: $priority, in: 1...100)
                    Stepper("Confidence: \(confidence)%", value: $confidence, in: 50...100, step: 5)
                }

                Section {
                    Button(action: saveRule) {
                        if isSubmitting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Text("Saving...")
                                Spacer()
                            }
                        } else {
                            Text("Add Rule")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(pattern.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Add Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func saveRule() {
        guard !isSubmitting else { return }
        isSubmitting = true

        Task {
            let request = CreateMatchingRuleRequest(
                merchantPattern: pattern,
                category: selectedCategory.rawValue,
                subcategory: nil,
                storeName: nil,
                isGrocery: selectedCategory == .grocery,
                isRestaurant: selectedCategory == .restaurant,
                isFoodRelated: selectedCategory == .grocery || selectedCategory == .restaurant,
                priority: priority,
                categoryId: nil,
                confidence: confidence,
                notes: nil
            )
            let success = await viewModel.createMatchingRule(request)
            if success {
                dismiss()
            } else {
                isSubmitting = false
            }
        }
    }
}

// MARK: - Recurring Item Row (Stub)

struct RecurringItemRow: View {
    let item: RecurringItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                Text(item.cadence.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(formatCurrency(item.amount, currency: item.currency))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(item.isExpense ? NexusTheme.Colors.Semantic.red : NexusTheme.Colors.Semantic.green)
        }
    }
}

// MARK: - Inline Plan Content (for tab embedding)

struct FinancePlanContent: View {
    @StateObject private var viewModel = FinancePlanningViewModel()
    @State private var selectedSection = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedSection) {
                Text("Categories").tag(0)
                Text("Recurring").tag(1)
                Text("Rules").tag(2)
                Text("Settings").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            TabView(selection: $selectedSection) {
                CategoriesListView(viewModel: viewModel)
                    .tag(0)

                RecurringItemsListView(viewModel: viewModel)
                    .tag(1)

                MatchingRulesListView(viewModel: viewModel)
                    .tag(2)

                FinanceSettingsView()
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .onAppear {
            viewModel.loadAll()
        }
    }
}

#Preview {
    FinancePlanningView()
}
