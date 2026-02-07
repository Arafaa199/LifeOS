import SwiftUI

struct ReceiptDetailView: View {
    @ObservedObject var viewModel: ReceiptsViewModel
    let receiptId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var itemToMatch: ReceiptItem?

    var body: some View {
        Group {
            if viewModel.isLoadingDetail {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading receipt...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let receipt = viewModel.selectedReceipt {
                receiptContent(receipt)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Receipt not found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .background(Color.nexusBackground)
        .navigationTitle("Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $itemToMatch) { item in
            NavigationView {
                FoodMatchSheet(viewModel: viewModel, item: item)
            }
        }
        .task {
            await viewModel.loadReceiptDetail(id: receiptId)
        }
    }

    @ViewBuilder
    private func receiptContent(_ receipt: ReceiptDetail) -> some View {
        List {
            headerSection(receipt)

            if let nutrition = viewModel.nutritionSummary, nutrition.matched_items > 0 {
                nutritionSection(nutrition)
            }

            itemsSection(receipt.items)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func headerSection(_ receipt: ReceiptDetail) -> some View {
        Section {
            row("Store", value: receipt.store_name ?? receipt.vendor)

            if let address = receipt.store_address {
                row("Address", value: address)
            }

            row("Date", value: formatDate(receipt.receipt_date))

            if let time = receipt.receipt_time {
                row("Time", value: formatTime(time))
            }

            if let invoiceNumber = receipt.invoice_number {
                row("Invoice", value: invoiceNumber)
            }

            if let subtotal = receipt.subtotal {
                row("Subtotal", value: formatAmount(subtotal, currency: receipt.currency))
            }

            if let vat = receipt.vat_amount {
                row("VAT", value: formatAmount(vat, currency: receipt.currency))
            }

            HStack {
                Text("Total")
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatAmount(receipt.total_amount, currency: receipt.currency))
                    .fontWeight(.semibold)
            }
        } header: {
            Text("Details")
        }
    }

    private func nutritionSection(_ nutrition: ReceiptNutritionSummary) -> some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    nutritionPill("Cal", value: Int(nutrition.total_calories), color: .nexusFood)
                    nutritionPill("P", value: Int(nutrition.total_protein), suffix: "g", color: .nexusPrimary)
                    nutritionPill("C", value: Int(nutrition.total_carbs), suffix: "g", color: .nexusWarning)
                    nutritionPill("F", value: Int(nutrition.total_fat), suffix: "g", color: .yellow)
                }

                Text("\(nutrition.matched_items) of \(nutrition.total_items) items linked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        } header: {
            Label("Nutrition Estimate", systemImage: "leaf.fill")
                .foregroundColor(.nexusFood)
        } footer: {
            Text("Based on matched items at default serving sizes")
        }
    }

    private func nutritionPill(_ label: String, value: Int, suffix: String = "", color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(color)
            Text("\(value)\(suffix)")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    private func itemsSection(_ items: [ReceiptItem]) -> some View {
        Section {
            ForEach(items) { item in
                ReceiptLineItemRow(item: item) {
                    itemToMatch = item
                }
            }
        } header: {
            Text("Items (\(items.count))")
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: dateStr) else { return dateStr }
        let output = DateFormatter()
        output.dateStyle = .long
        return output.string(from: date)
    }

    private func formatTime(_ timeStr: String) -> String {
        let parts = timeStr.split(separator: ":")
        guard parts.count >= 2 else { return timeStr }
        return "\(parts[0]):\(parts[1])"
    }

    private func formatAmount(_ amount: Double, currency: String) -> String {
        if currency == "AED" {
            return String(format: "%.2f AED", amount)
        }
        return String(format: "%.2f %@", amount, currency)
    }
}

struct ReceiptLineItemRow: View {
    let item: ReceiptItem
    let onLinkTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        if let qty = item.quantity, qty != 1 {
                            Text("\(Int(qty))×")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let unitPrice = item.unit_price {
                            Text(String(format: "%.2f", unitPrice))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if item.is_promotional == true {
                            Text("PROMO")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.nexusSuccess)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.nexusSuccess.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                Text(String(format: "%.2f", item.line_total))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            if item.isMatched {
                matchedFoodInfo
            } else {
                linkButton
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var matchedFoodInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.caption)
                .foregroundColor(.nexusFood)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.food_name ?? "Linked")
                    .font(.caption)
                    .foregroundColor(.nexusFood)

                if let brand = item.food_brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let cal = item.calories_per_100g {
                HStack(spacing: 4) {
                    Text("\(Int(cal))")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("cal/100g")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if item.is_user_confirmed == true {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.nexusSuccess)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.nexusFood.opacity(0.1))
        .cornerRadius(8)
    }

    private var linkButton: some View {
        Button(action: onLinkTapped) {
            HStack {
                Image(systemName: "link")
                    .font(.caption)
                Text("Link to food")
                    .font(.caption)
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
