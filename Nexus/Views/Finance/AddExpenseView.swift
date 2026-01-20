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
                        if viewModel.isLoading {
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
                    .disabled(merchantName.isEmpty || amount.isEmpty || viewModel.isLoading)
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
        guard let amountValue = Double(amount) else {
            errorMessage = "Invalid amount"
            showingError = true
            return
        }

        Task {
            await viewModel.addManualTransaction(
                merchantName: merchantName,
                amount: amountValue,
                category: selectedCategory.rawValue,
                notes: notes.isEmpty ? nil : notes,
                date: date
            )

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
