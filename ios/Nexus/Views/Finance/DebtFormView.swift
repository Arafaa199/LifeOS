import SwiftUI

struct DebtFormView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var creditor = ""
    @State private var debtType = "bnpl"
    @State private var originalAmount = ""
    @State private var remainingAmount = ""
    @State private var installmentAmount = ""
    @State private var installmentsTotal = ""
    @State private var installmentsPaid = ""
    @State private var cadence = "monthly"
    @State private var nextDueDate = Date()
    @State private var hasNextDueDate = true
    @State private var finalDueDate = Date()
    @State private var hasFinalDueDate = false
    @State private var interestRate = ""
    @State private var priority = 5
    @State private var notes = ""
    @State private var remindersEnabled = true
    @State private var isSaving = false

    private let debtTypes = [
        ("bnpl", "BNPL"),
        ("credit_card", "Credit Card"),
        ("loan", "Loan"),
        ("one_off", "One-off"),
        ("family", "Family"),
        ("other", "Other")
    ]

    private let cadences = [
        ("one_off", "One-off"),
        ("weekly", "Weekly"),
        ("biweekly", "Biweekly"),
        ("monthly", "Monthly"),
        ("quarterly", "Quarterly")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Creditor", text: $creditor)
                    Picker("Type", selection: $debtType) {
                        ForEach(debtTypes, id: \.0) { type in
                            Text(type.1).tag(type.0)
                        }
                    }
                }

                Section("Amounts") {
                    HStack {
                        Text("AED")
                            .foregroundColor(.secondary)
                        TextField("Original Amount", text: $originalAmount)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("AED")
                            .foregroundColor(.secondary)
                        TextField("Remaining Amount", text: $remainingAmount)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("AED")
                            .foregroundColor(.secondary)
                        TextField("Installment Amount", text: $installmentAmount)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("%")
                            .foregroundColor(.secondary)
                        TextField("Interest Rate (annual)", text: $interestRate)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Schedule") {
                    Picker("Payment Cadence", selection: $cadence) {
                        ForEach(cadences, id: \.0) { c in
                            Text(c.1).tag(c.0)
                        }
                    }

                    if cadence != "one_off" {
                        HStack {
                            TextField("Total Installments", text: $installmentsTotal)
                                .keyboardType(.numberPad)
                            Text("paid:")
                                .foregroundColor(.secondary)
                            TextField("0", text: $installmentsPaid)
                                .keyboardType(.numberPad)
                                .frame(width: 40)
                        }
                    }

                    Toggle("Next Due Date", isOn: $hasNextDueDate)
                    if hasNextDueDate {
                        DatePicker("Due", selection: $nextDueDate, displayedComponents: .date)
                    }

                    Toggle("Final Due Date", isOn: $hasFinalDueDate)
                    if hasFinalDueDate {
                        DatePicker("Final", selection: $finalDueDate, displayedComponents: .date)
                    }
                }

                Section("Options") {
                    Picker("Priority", selection: $priority) {
                        Text("Highest").tag(1)
                        Text("High").tag(2)
                        Text("Medium").tag(3)
                        Text("Normal").tag(5)
                        Text("Low").tag(7)
                    }
                    Toggle("Auto-reminders", isOn: $remindersEnabled)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle("Add Debt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!isValid || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var isValid: Bool {
        !name.isEmpty && Double(originalAmount) != nil && Double(remainingAmount) != nil
    }

    private func save() {
        guard let original = Double(originalAmount),
              let remaining = Double(remainingAmount) else { return }

        isSaving = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let request = CreateDebtRequest(
            name: name,
            creditor: creditor.isEmpty ? nil : creditor,
            debtType: debtType,
            originalAmount: original,
            remainingAmount: remaining,
            currency: "AED",
            interestRate: Double(interestRate),
            installmentAmount: Double(installmentAmount),
            installmentsTotal: Int(installmentsTotal),
            installmentsPaid: Int(installmentsPaid),
            cadence: cadence,
            nextDueDate: hasNextDueDate ? formatter.string(from: nextDueDate) : nil,
            finalDueDate: hasFinalDueDate ? formatter.string(from: finalDueDate) : nil,
            priority: priority,
            notes: notes.isEmpty ? nil : notes,
            remindersEnabled: remindersEnabled
        )

        Task {
            let success = await viewModel.createDebt(request)
            if success { dismiss() }
            isSaving = false
        }
    }
}

#Preview {
    DebtFormView(viewModel: FinanceViewModel())
}
