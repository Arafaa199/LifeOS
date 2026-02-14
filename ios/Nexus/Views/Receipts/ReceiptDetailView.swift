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
        .background(NexusTheme.Colors.background)
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

            if let date = receipt.receipt_date {
                row("Date", value: formatDate(date))
            }

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Receipt header: \(receipt.store_name ?? receipt.vendor), \(receipt.receipt_date.map { formatDate($0) } ?? ""), total \(formatAmount(receipt.total_amount, currency: receipt.currency))")
    }

    private func nutritionSection(_ nutrition: ReceiptNutritionSummary) -> some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    nutritionPill("Cal", value: Int(nutrition.total_calories), color: NexusTheme.Colors.Semantic.amber)
                    nutritionPill("P", value: Int(nutrition.total_protein), suffix: "g", color: NexusTheme.Colors.accent)
                    nutritionPill("C", value: Int(nutrition.total_carbs), suffix: "g", color: NexusTheme.Colors.Semantic.amber)
                    nutritionPill("F", value: Int(nutrition.total_fat), suffix: "g", color: .yellow)
                }

                Text("\(nutrition.matched_items) of \(nutrition.total_items) items linked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        } header: {
            Label("Nutrition Estimate", systemImage: "leaf.fill")
                .foregroundColor(NexusTheme.Colors.Semantic.amber)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)\(suffix)")
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
        let dateOnly = String(dateStr.prefix(10))
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: dateOnly) else { return dateOnly }
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
                                .foregroundColor(NexusTheme.Colors.Semantic.green)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(NexusTheme.Colors.Semantic.green.opacity(0.15))
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Item: \(item.displayDescription)\(item.quantity.map { ", quantity \($0)" } ?? ""), price \(String(format: "%.2f", item.line_total))")
        .accessibilityHint("Double tap to link this item to a food entry")
    }

    @ViewBuilder
    private var matchedFoodInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.caption)
                .foregroundColor(NexusTheme.Colors.Semantic.amber)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.food_name ?? "Linked")
                    .font(.caption)
                    .foregroundColor(NexusTheme.Colors.Semantic.amber)

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
                    .foregroundColor(NexusTheme.Colors.Semantic.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(NexusTheme.Colors.Semantic.amber.opacity(0.1))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Matched food: \(item.food_name ?? "Linked")\(item.food_brand.map { ", \($0)" } ?? "")\(item.calories_per_100g.map { ", \(Int($0)) calories per 100 grams" } ?? "")")
        .accessibilityHint("Linked to nutrition database\(item.is_user_confirmed == true ? ", confirmed by user" : "")")
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
        .accessibilityLabel("Link to food")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to match this receipt item to a food database entry for nutrition tracking")
    }
}
