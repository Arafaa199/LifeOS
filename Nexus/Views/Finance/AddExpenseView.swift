import SwiftUI

struct AddExpenseView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinanceViewModel

    @State private var merchantName = ""
    @State private var amount = ""
    @State private var selectedCategory: ExpenseCategory = .other
    @State private var notes = ""
    @State private var date = Date()
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationView {
            Form {
                Section("Transaction Details") {
                    TextField("Merchant Name", text: $merchantName)
                        .autocapitalization(.words)

                    HStack {
                        Text("AED")
                            .foregroundColor(.secondary)
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
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
                    .pickerStyle(.menu)
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section {
                    Button(action: saveExpense) {
                        if isSubmitting || viewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            HStack {
                                Spacer()
                                Text("Add Expense")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                    .disabled(merchantName.isEmpty || amount.isEmpty || isSubmitting || viewModel.isLoading)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func saveExpense() {
        // Prevent double-submit
        guard !isSubmitting else { return }

        guard let amountValue = Double(amount) else {
            errorMessage = "Invalid amount"
            showingError = true
            return
        }

        // Expenses are stored as negative amounts
        let expenseAmount = -abs(amountValue)

        // Set immediately (synchronous) to prevent double-tap
        isSubmitting = true

        Task {
            await viewModel.addManualTransaction(
                merchantName: merchantName,
                amount: expenseAmount,
                category: selectedCategory.rawValue,
                notes: notes.isEmpty ? nil : notes,
                date: date
            )

            isSubmitting = false

            if viewModel.errorMessage == nil {
                dismiss()
            } else {
                errorMessage = viewModel.errorMessage ?? "Failed to add expense"
                showingError = true
            }
        }
    }
}

#Preview {
    AddExpenseView(viewModel: FinanceViewModel())
}
