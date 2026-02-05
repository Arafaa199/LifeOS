import SwiftUI

struct BudgetSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var budgets: [BudgetItem] = []
    @State private var showingAddBudget = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let api = NexusAPI.shared

    var body: some View {
        NavigationView {
            List {
                if budgets.isEmpty && !isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Budgets Set")
                            .font(.headline)
                        Text("Add monthly budgets to track your spending")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(budgets) { budget in
                        BudgetRow(budget: budget)
                    }
                    .onDelete(perform: deleteBudgets)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.nexusError)
                        .font(.caption)
                }
            }
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddBudget = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddBudget) {
                AddBudgetView { category, amount in
                    Task {
                        await addBudget(category: category, amount: amount)
                    }
                }
            }
            .onAppear {
                Task {
                    await loadBudgets()
                }
            }
        }
    }

    private func loadBudgets() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.fetchBudgets()
            if response.success, let data = response.data {
                budgets = data.budgets.map { budget in
                    BudgetItem(
                        id: budget.id ?? 0,
                        category: budget.category,
                        amount: budget.budgetAmount,
                        spent: budget.spent ?? 0
                    )
                }
            }
        } catch {
            errorMessage = "Failed to load budgets: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func addBudget(category: String, amount: Double) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.setBudget(category: category, amount: amount)
            if response.success {
                await loadBudgets()
            } else {
                errorMessage = response.message ?? "Failed to add budget"
            }
        } catch {
            errorMessage = "Failed to add budget: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func deleteBudgets(at offsets: IndexSet) {
        for offset in offsets {
            let budget = budgets[offset]
            Task {
                await deleteBudget(id: budget.id)
            }
        }
    }

    private func deleteBudget(id: Int) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.deleteBudget(id: id)
            if response.success {
                await loadBudgets()
            } else {
                errorMessage = response.message ?? "Failed to delete budget"
            }
        } catch {
            errorMessage = "Failed to delete budget: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

struct BudgetItem: Identifiable {
    let id: Int
    let category: String
    let amount: Double
    var spent: Double
}

struct BudgetRow: View {
    let budget: BudgetItem

    private var progress: Double {
        min(budget.spent / budget.amount, 1.0)
    }

    private var isOverBudget: Bool {
        budget.spent > budget.amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(budget.category)
                    .font(.headline)
                Spacer()
                Text(String(format: "AED %.0f / %.0f", budget.spent, budget.amount))
                    .font(.subheadline)
                    .foregroundColor(isOverBudget ? .nexusError : .secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.tertiarySystemBackground))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(isOverBudget ? Color.nexusError : Color.nexusFinance)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)

            HStack {
                Text(budget.spent >= budget.amount
                     ? String(format: "AED %.0f over budget", budget.spent - budget.amount)
                     : String(format: "AED %.0f remaining", budget.amount - budget.spent))
                    .font(.caption)
                    .foregroundColor(isOverBudget ? .nexusError : .secondary)

                Spacer()

                Text(String(format: "%.0f%%", progress * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct AddBudgetView: View {
    @Environment(\.dismiss) var dismiss
    let onAdd: (String, Double) -> Void

    @State private var selectedCategory: ExpenseCategory = .grocery
    @State private var amount = ""

    var body: some View {
        NavigationView {
            Form {
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

                Section("Monthly Budget") {
                    HStack {
                        Text("AED")
                            .foregroundColor(.secondary)
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                }

                Section {
                    Button("Add Budget") {
                        if let amountValue = Double(amount) {
                            onAdd(selectedCategory.rawValue, amountValue)
                            dismiss()
                        }
                    }
                    .disabled(amount.isEmpty)
                }
            }
            .navigationTitle("Add Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    BudgetSettingsView()
}
