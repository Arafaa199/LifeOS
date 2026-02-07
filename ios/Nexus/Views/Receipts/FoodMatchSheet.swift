import SwiftUI

struct FoodMatchSheet: View {
    @ObservedObject var viewModel: ReceiptsViewModel
    let item: ReceiptItem
    @Environment(\.dismiss) private var dismiss
    @State private var isMatching = false

    var body: some View {
        VStack(spacing: 0) {
            itemHeader

            FoodSearchView { selectedFood in
                Task {
                    isMatching = true
                    let success = await viewModel.matchItemToFood(
                        itemId: item.id,
                        foodId: selectedFood.id
                    )
                    isMatching = false
                    if success {
                        dismiss()
                    }
                }
            }
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle("Link to Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .overlay {
            if isMatching {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Linking...")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var itemHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receipt Item")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(item.displayDescription)
                .font(.headline)

            HStack(spacing: 12) {
                if let qty = item.quantity, qty != 1 {
                    Label("\(Int(qty))×", systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Label(String(format: "%.2f", item.line_total), systemImage: "tag")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
    }
}

