import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinanceViewModel
    let transaction: Transaction

    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false

    var body: some View {
        NavigationView {
            List {
                Section("Transaction Details") {
                    HStack {
                        Text("Merchant")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(transaction.merchantName)
                    }

                    HStack {
                        Text("Amount")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(transaction.displayAmount)
                            .fontWeight(.semibold)
                            .foregroundColor(transaction.amount < 0 ? .red : .green)
                    }

                    HStack {
                        Text("Date")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(transaction.date, style: .date)
                    }

                    if let category = transaction.category {
                        HStack {
                            Text("Category")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(category)
                        }
                    }

                    if let subcategory = transaction.subcategory {
                        HStack {
                            Text("Subcategory")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(subcategory)
                        }
                    }
                }

                if let notes = transaction.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .foregroundColor(.secondary)
                    }
                }

                if let tags = transaction.tags, !tags.isEmpty {
                    Section("Tags") {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                        }
                    }
                }

                Section("Flags") {
                    if transaction.isGrocery {
                        Label("Grocery Purchase", systemImage: "cart.fill")
                            .foregroundColor(.green)
                    }
                    if transaction.isRestaurant {
                        Label("Restaurant/Food", systemImage: "fork.knife")
                            .foregroundColor(.orange)
                    }
                }

                Section {
                    Button(action: { showingEditSheet = true }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Edit Transaction")
                        }
                    }

                    Button(role: .destructive, action: { showingDeleteAlert = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Transaction")
                        }
                    }
                }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                EditTransactionView(viewModel: viewModel, transaction: transaction)
            }
            .alert("Delete Transaction", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteTransaction()
                    }
                }
            } message: {
                Text("Are you sure you want to delete this transaction? This cannot be undone.")
            }
        }
    }

    private func deleteTransaction() async {
        guard let id = transaction.id else { return }
        await viewModel.deleteTransaction(id: id)
        dismiss()
    }
}

struct EditTransactionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinanceViewModel
    let transaction: Transaction

    @State private var merchantName: String
    @State private var amount: String
    @State private var selectedCategory: String
    @State private var notes: String
    @State private var date: Date

    init(viewModel: FinanceViewModel, transaction: Transaction) {
        self.viewModel = viewModel
        self.transaction = transaction
        _merchantName = State(initialValue: transaction.merchantName)
        _amount = State(initialValue: String(format: "%.2f", abs(transaction.amount)))
        _selectedCategory = State(initialValue: transaction.category ?? "Other")
        _notes = State(initialValue: transaction.notes ?? "")
        _date = State(initialValue: transaction.date)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Transaction Details") {
                    TextField("Merchant Name", text: $merchantName)
                        .autocapitalization(.words)

                    HStack {
                        Text(transaction.currency)
                            .foregroundColor(.secondary)
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category.rawValue)
                        }
                    }
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section {
                    Button(action: saveChanges) {
                        if viewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            HStack {
                                Spacer()
                                Text("Save Changes")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                    .disabled(merchantName.isEmpty || amount.isEmpty || viewModel.isLoading)
                }
            }
            .navigationTitle("Edit Transaction")
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

    private func saveChanges() {
        guard let amountValue = Double(amount),
              let id = transaction.id else { return }

        Task {
            await viewModel.updateTransaction(
                id: id,
                merchantName: merchantName,
                amount: amountValue,
                category: selectedCategory,
                notes: notes.isEmpty ? nil : notes,
                date: date
            )
            dismiss()
        }
    }
}
