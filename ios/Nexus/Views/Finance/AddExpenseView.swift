import SwiftUI
import UIKit

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
    @State private var showingSuggestions = false
    @State private var showDuplicateWarning = false

    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private let successHaptics = UINotificationFeedbackGenerator()

    // Recent merchants for autocomplete
    private var recentMerchants: [String] {
        let merchants = viewModel.recentTransactions
            .map { $0.merchantName }
            .filter { !$0.isEmpty }

        // Unique, sorted by frequency
        var counts: [String: Int] = [:]
        for merchant in merchants {
            counts[merchant, default: 0] += 1
        }

        return counts.sorted { $0.value > $1.value }
            .map { $0.key }
            .prefix(10)
            .map { $0 }
    }

    // Filter suggestions based on input
    private var filteredSuggestions: [String] {
        guard !merchantName.isEmpty else { return Array(recentMerchants.prefix(5)) }
        return recentMerchants.filter {
            $0.localizedCaseInsensitiveContains(merchantName)
        }.prefix(5).map { $0 }
    }

    // Check for potential duplicate
    private var potentialDuplicate: Transaction? {
        guard let amountDouble = Double(amount), !merchantName.isEmpty else { return nil }

        let calendar = Calendar.current
        return viewModel.recentTransactions.first { tx in
            let sameMerchant = tx.merchantName.localizedCaseInsensitiveCompare(merchantName) == .orderedSame
            let sameAmount = abs(abs(tx.amount) - amountDouble) < 0.01
            let sameDay = calendar.isDate(tx.date, inSameDayAs: date)
            return sameMerchant && sameAmount && sameDay
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Transaction Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Merchant Name", text: $merchantName)
                            .autocapitalization(.words)
                            .onChange(of: merchantName) {
                                showingSuggestions = !merchantName.isEmpty && !filteredSuggestions.isEmpty
                            }

                        // Merchant suggestions
                        if showingSuggestions && !filteredSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(filteredSuggestions, id: \.self) { suggestion in
                                        Button {
                                            merchantName = suggestion
                                            showingSuggestions = false
                                            haptics.impactOccurred()
                                        } label: {
                                            Text(suggestion)
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(NexusTheme.Colors.accent.opacity(0.15))
                                                .foregroundColor(NexusTheme.Colors.accent)
                                                .cornerRadius(NexusTheme.Radius.sm)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Text(AppSettings.shared.defaultCurrency)
                            .foregroundColor(.secondary)
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                            .onChange(of: amount) {
                                // Check for duplicate when amount changes
                                showDuplicateWarning = potentialDuplicate != nil
                            }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .onChange(of: date) {
                            showDuplicateWarning = potentialDuplicate != nil
                        }
                }

                // Duplicate warning
                if showDuplicateWarning, let duplicate = potentialDuplicate {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(NexusTheme.Colors.Semantic.amber)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Possible Duplicate")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(NexusTheme.Colors.Semantic.amber)

                                Text("A similar transaction exists: \(duplicate.merchantName) for \(formatCurrency(abs(duplicate.amount), currency: duplicate.currency))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
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
                    .onChange(of: selectedCategory) {
                        haptics.impactOccurred()
                    }
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
                                Text("Saving...")
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 8)
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
            .scrollDismissesKeyboard(.interactively)
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
            haptics.impactOccurred()
            successHaptics.notificationOccurred(.error)
            errorMessage = "Invalid amount"
            showingError = true
            return
        }

        // Expenses are stored as negative amounts
        let expenseAmount = -abs(amountValue)

        // Set immediately (synchronous) to prevent double-tap
        isSubmitting = true

        Task {
            // Use returned success bool - don't rely on errorMessage
            let success = await viewModel.addManualTransaction(
                merchantName: merchantName,
                amount: expenseAmount,
                category: selectedCategory.rawValue,
                notes: notes.isEmpty ? nil : notes,
                date: date
            )

            // Always dismiss on success (including offline queue)
            if success {
                successHaptics.notificationOccurred(.success)
                dismiss()
            } else {
                successHaptics.notificationOccurred(.error)
                isSubmitting = false
                errorMessage = viewModel.errorMessage ?? "Failed to add expense"
                showingError = true
            }
        }
    }
}

#Preview {
    AddExpenseView(viewModel: FinanceViewModel())
}
