import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinanceViewModel
    let transaction: Transaction

    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingCorrectionSheet = false
    @State private var showingRevertAlert = false

    var body: some View {
        NavigationView {
            List {
                // Correction banner if corrected
                if transaction.hasCorrection {
                    Section {
                        HStack {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("Corrected")
                                    .font(.headline)
                                if let reason = transaction.correctionReason {
                                    Text(reason.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button("Revert") {
                                showingRevertAlert = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }
                    }
                }

                Section("Transaction Details") {
                    DetailRow(label: "Merchant", value: transaction.merchantName)

                    HStack {
                        Text("Amount")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(transaction.displayAmount)
                            .fontWeight(.semibold)
                            .foregroundColor(transaction.amount < 0 ? .red : .green)
                    }

                    DetailRow(label: "Date", value: transaction.date.formatted(date: .abbreviated, time: .omitted))

                    if let category = transaction.category {
                        DetailRow(label: "Category", value: category)
                    }

                    if let subcategory = transaction.subcategory {
                        DetailRow(label: "Subcategory", value: subcategory)
                    }

                    if let source = transaction.source {
                        DetailRow(label: "Source", value: transaction.sourceDisplay)
                    }
                }

                // Original values section (only if corrected)
                if transaction.hasCorrection {
                    Section("Original Values") {
                        if let original = transaction.originalMerchantName, original != transaction.merchantName {
                            DetailRow(label: "Merchant", value: original, isStrikethrough: true)
                        }
                        if let original = transaction.originalAmount, original != transaction.amount {
                            DetailRow(label: "Amount", value: String(format: "%@ %.2f", transaction.currency, abs(original)), isStrikethrough: true)
                        }
                        if let original = transaction.originalCategory, original != transaction.category {
                            DetailRow(label: "Category", value: original, isStrikethrough: true)
                        }
                        if let notes = transaction.correctionNotes, !notes.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Correction Notes")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Text(notes)
                                    .font(.subheadline)
                            }
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
                    if !transaction.isGrocery && !transaction.isRestaurant {
                        Text("None")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(action: { showingCorrectionSheet = true }) {
                        HStack {
                            Image(systemName: "pencil.and.outline")
                            Text(transaction.hasCorrection ? "Edit Correction" : "Create Correction")
                        }
                    }

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
            .sheet(isPresented: $showingCorrectionSheet) {
                CorrectionView(viewModel: viewModel, transaction: transaction)
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
            .alert("Revert Correction", isPresented: $showingRevertAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Revert", role: .destructive) {
                    Task {
                        await revertCorrection()
                    }
                }
            } message: {
                Text("This will restore the original values from the SMS/import. The correction will be deactivated but kept for audit.")
            }
        }
    }

    private func deleteTransaction() async {
        guard let id = transaction.id else { return }
        await viewModel.deleteTransaction(id: id)
        dismiss()
    }

    private func revertCorrection() async {
        guard let correctionId = transaction.correctionId else { return }
        await viewModel.deactivateCorrection(correctionId: correctionId)
        dismiss()
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var isStrikethrough: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            if isStrikethrough {
                Text(value)
                    .strikethrough()
                    .foregroundColor(.secondary)
            } else {
                Text(value)
            }
        }
    }
}

// MARK: - Correction View

struct CorrectionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinanceViewModel
    let transaction: Transaction

    @State private var correctedAmount: String
    @State private var correctedCategory: String
    @State private var correctedMerchant: String
    @State private var correctedDate: Date
    @State private var selectedReason: CorrectionReason = .other
    @State private var notes: String = ""

    @State private var changeAmount = false
    @State private var changeCategory = false
    @State private var changeMerchant = false
    @State private var changeDate = false

    init(viewModel: FinanceViewModel, transaction: Transaction) {
        self.viewModel = viewModel
        self.transaction = transaction
        _correctedAmount = State(initialValue: String(format: "%.2f", abs(transaction.amount)))
        _correctedCategory = State(initialValue: transaction.category ?? "Other")
        _correctedMerchant = State(initialValue: transaction.merchantName)
        _correctedDate = State(initialValue: transaction.date)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Creating a correction preserves the original data while showing corrected values.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Original: \(transaction.merchantName) - \(transaction.displayAmount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("What needs correcting?") {
                    Toggle("Amount", isOn: $changeAmount)
                    if changeAmount {
                        HStack {
                            Text(transaction.currency)
                                .foregroundColor(.secondary)
                            TextField("Amount", text: $correctedAmount)
                                .keyboardType(.decimalPad)
                        }
                        .padding(.leading, 20)
                    }

                    Toggle("Category", isOn: $changeCategory)
                    if changeCategory {
                        Picker("Category", selection: $correctedCategory) {
                            ForEach(ExpenseCategory.allCases, id: \.self) { category in
                                Text(category.rawValue).tag(category.rawValue)
                            }
                        }
                        .padding(.leading, 20)
                    }

                    Toggle("Merchant Name", isOn: $changeMerchant)
                    if changeMerchant {
                        TextField("Merchant", text: $correctedMerchant)
                            .padding(.leading, 20)
                    }

                    Toggle("Date", isOn: $changeDate)
                    if changeDate {
                        DatePicker("Date", selection: $correctedDate, displayedComponents: .date)
                            .padding(.leading, 20)
                    }
                }

                Section("Reason for Correction") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(CorrectionReason.allCases, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                Section {
                    Button(action: saveCorrection) {
                        if viewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            HStack {
                                Spacer()
                                Text("Save Correction")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                    .disabled(!hasChanges || viewModel.isLoading)
                }
            }
            .navigationTitle("Correct Transaction")
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

    private var hasChanges: Bool {
        changeAmount || changeCategory || changeMerchant || changeDate
    }

    private func saveCorrection() {
        guard let transactionId = transaction.id else { return }

        Task {
            let success = await viewModel.createCorrection(
                transactionId: transactionId,
                amount: changeAmount ? Double(correctedAmount) : nil,
                category: changeCategory ? correctedCategory : nil,
                merchantName: changeMerchant ? correctedMerchant : nil,
                date: changeDate ? correctedDate : nil,
                reason: selectedReason,
                notes: notes.isEmpty ? nil : notes
            )

            if success {
                dismiss()
            }
        }
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
