import SwiftUI

struct RecurringItemFormView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: FinanceViewModel
    let editingItem: RecurringItem?

    @State private var name: String = ""
    @State private var amount: String = ""
    @State private var type: String = "expense"
    @State private var cadence: String = "monthly"
    @State private var dayOfMonth: Int = 1
    @State private var nextDueDate: Date = Date()
    @State private var notes: String = ""
    @State private var isSubmitting = false

    var isEditing: Bool { editingItem != nil }

    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Name (e.g., Rent, Netflix)", text: $name)

                    HStack {
                        Text(AppSettings.shared.defaultCurrency)
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

                    DatePicker("Next Due Date", selection: $nextDueDate, displayedComponents: .date)

                    if cadence == "monthly" {
                        Picker("Day of Month", selection: $dayOfMonth) {
                            ForEach(1...28, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                    }
                }

                if !notes.isEmpty || isEditing {
                    Section("Notes") {
                        TextField("Notes (optional)", text: $notes)
                    }
                }

                Section {
                    Button(action: save) {
                        if isSubmitting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Text("Saving...")
                                Spacer()
                            }
                        } else {
                            Text(isEditing ? "Update" : "Add Recurring Item")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(name.isEmpty || amount.isEmpty || isSubmitting)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                if let item = editingItem {
                                    isSubmitting = true
                                    let success = await viewModel.deleteRecurringItem(id: item.id)
                                    if success { dismiss() }
                                    isSubmitting = false
                                }
                            }
                        } label: {
                            Text("Delete")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Recurring" : "Add Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let item = editingItem {
                    name = item.name
                    amount = String(format: "%.0f", item.amount)
                    type = item.type
                    cadence = item.cadence
                    dayOfMonth = item.dayOfMonth ?? 1
                    nextDueDate = item.nextDueDate ?? Date()
                    notes = item.notes ?? ""
                }
            }
        }
    }

    private func save() {
        guard !isSubmitting, let amountValue = Double(amount) else { return }
        isSubmitting = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dueDateString = formatter.string(from: nextDueDate)

        Task {
            var success = false
            if let item = editingItem {
                let request = UpdateRecurringItemRequest(
                    id: item.id,
                    name: name,
                    amount: amountValue,
                    type: type,
                    cadence: cadence,
                    dayOfMonth: cadence == "monthly" ? dayOfMonth : nil,
                    nextDueDate: dueDateString,
                    merchantPattern: nil,
                    notes: notes.isEmpty ? nil : notes
                )
                success = await viewModel.updateRecurringItem(request)
            } else {
                let request = CreateRecurringItemRequest(
                    name: name,
                    amount: amountValue,
                    currency: "AED",
                    type: type,
                    cadence: cadence,
                    dayOfMonth: cadence == "monthly" ? dayOfMonth : nil,
                    dayOfWeek: nil,
                    nextDueDate: dueDateString,
                    categoryId: nil,
                    merchantPattern: nil,
                    autoCreate: false,
                    notes: notes.isEmpty ? nil : notes
                )
                success = await viewModel.createRecurringItem(request)
            }

            if success {
                dismiss()
            } else {
                isSubmitting = false
            }
        }
    }
}
