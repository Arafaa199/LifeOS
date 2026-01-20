import SwiftUI

struct IncomeView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinanceViewModel

    @State private var source = ""
    @State private var amount = ""
    @State private var selectedCategory: IncomeCategory = .salary
    @State private var notes = ""
    @State private var date = Date()
    @State private var isRecurring = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Income Details") {
                    TextField("Income Source", text: $source)
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
                        ForEach(IncomeCategory.allCases, id: \.self) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue)
                            }
                            .tag(category)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Recurring Income", isOn: $isRecurring)
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section {
                    Button(action: saveIncome) {
                        if viewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            HStack {
                                Spacer()
                                Text("Add Income")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                    .disabled(source.isEmpty || amount.isEmpty || viewModel.isLoading)
                }
            }
            .navigationTitle("Add Income")
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

    private func saveIncome() {
        guard let amountValue = Double(amount) else {
            errorMessage = "Invalid amount"
            showingError = true
            return
        }

        Task {
            await viewModel.addIncome(
                source: source,
                amount: amountValue,
                category: selectedCategory.rawValue,
                notes: notes.isEmpty ? nil : notes,
                date: date,
                isRecurring: isRecurring
            )

            if viewModel.errorMessage == nil {
                dismiss()
            } else {
                errorMessage = viewModel.errorMessage ?? "Failed to add income"
                showingError = true
            }
        }
    }
}

enum IncomeCategory: String, CaseIterable {
    case salary = "Salary"
    case freelance = "Freelance"
    case investment = "Investment"
    case rental = "Rental"
    case business = "Business"
    case gift = "Gift"
    case refund = "Refund"
    case other = "Other"

    var icon: String {
        switch self {
        case .salary: return "banknote"
        case .freelance: return "briefcase"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .rental: return "house"
        case .business: return "building.2"
        case .gift: return "gift"
        case .refund: return "arrow.uturn.backward"
        case .other: return "ellipsis.circle"
        }
    }
}

#Preview {
    IncomeView(viewModel: FinanceViewModel())
}
