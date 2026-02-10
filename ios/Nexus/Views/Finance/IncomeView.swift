import SwiftUI
import UIKit

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
    @State private var isSubmitting = false

    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private let successHaptics = UINotificationFeedbackGenerator()

    var body: some View {
        NavigationView {
            Form {
                Section("Income Details") {
                    TextField("Income Source", text: $source)
                        .autocapitalization(.words)

                    HStack {
                        Text(AppSettings.shared.defaultCurrency)
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
                    .onChange(of: selectedCategory) {
                        haptics.impactOccurred()
                    }

                    Toggle("Recurring Income", isOn: $isRecurring)
                        .onChange(of: isRecurring) {
                            haptics.impactOccurred()
                        }
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section {
                    Button(action: saveIncome) {
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
                                Text("Add Income")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                    .disabled(source.isEmpty || amount.isEmpty || isSubmitting || viewModel.isLoading)
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
        // Prevent double-submit
        guard !isSubmitting else { return }

        guard let amountValue = Double(amount) else {
            haptics.impactOccurred()
            successHaptics.notificationOccurred(.error)
            errorMessage = "Invalid amount"
            showingError = true
            return
        }

        // Income is always positive
        let incomeAmount = abs(amountValue)

        // Set immediately (synchronous) to prevent double-tap
        isSubmitting = true

        Task {
            // Use returned success bool - don't rely on errorMessage
            let success = await viewModel.addIncome(
                source: source,
                amount: incomeAmount,
                category: selectedCategory.rawValue,
                notes: notes.isEmpty ? nil : notes,
                date: date,
                isRecurring: isRecurring
            )

            // Always dismiss on success (including offline queue)
            if success {
                successHaptics.notificationOccurred(.success)
                dismiss()
            } else {
                successHaptics.notificationOccurred(.error)
                isSubmitting = false
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
