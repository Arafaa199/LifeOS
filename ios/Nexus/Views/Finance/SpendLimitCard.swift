import SwiftUI

struct SpendLimitCard: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingEditor = false
    @State private var editAmount = ""

    var body: some View {
        if let limit = viewModel.spendLimit {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly Spend Limit")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(formatCurrency(limit.limitAmount, currency: limit.currency))
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    Spacer()
                    Button(action: {
                        editAmount = String(format: "%.0f", limit.limitAmount)
                        showingEditor = true
                    }) {
                        Image(systemName: "pencil.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }

                let spent = viewModel.summary.totalSpent
                let progress = limit.limitAmount > 0 ? min(spent / limit.limitAmount, 1.0) : 0
                let color = progressColor(progress)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 8)
                            .cornerRadius(4)
                        Rectangle()
                            .fill(color)
                            .frame(width: geo.size.width * progress, height: 8)
                            .cornerRadius(4)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(formatCurrency(spent, currency: limit.currency) + " spent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    let remaining = limit.limitAmount - spent
                    Text(formatCurrency(max(remaining, 0), currency: limit.currency) + " left")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(remaining >= 0 ? .nexusSuccess : .nexusError)
                }
            }
            .padding()
            .background(Color.nexusCardBackground)
            .cornerRadius(16)
            .alert("Set Spend Limit", isPresented: $showingEditor) {
                TextField("Amount", text: $editAmount)
                    .keyboardType(.decimalPad)
                Button("Save") {
                    if let amount = Double(editAmount) {
                        Task { await viewModel.setSpendLimit(amount: amount) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Monthly discretionary spending limit (AED)")
            }
        } else {
            Button(action: {
                editAmount = "8000"
                showingEditor = true
            }) {
                HStack {
                    Image(systemName: "gauge.with.needle")
                        .foregroundColor(.nexusFinance)
                    Text("Set Monthly Spend Limit")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.nexusCardBackground)
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .alert("Set Spend Limit", isPresented: $showingEditor) {
                TextField("Amount", text: $editAmount)
                    .keyboardType(.decimalPad)
                Button("Save") {
                    if let amount = Double(editAmount) {
                        Task { await viewModel.setSpendLimit(amount: amount) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Monthly discretionary spending limit (AED)")
            }
        }
    }

    private func progressColor(_ progress: Double) -> Color {
        if progress > 0.9 { return .nexusError }
        if progress > 0.7 { return .nexusWarning }
        return .nexusFinance
    }
}
