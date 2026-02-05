import SwiftUI

struct WishlistView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showingAddItem = false
    @State private var newName = ""
    @State private var newCost = ""
    @State private var newPriority = 5
    @State private var newUrl = ""
    @State private var newNotes = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.wishlistItems.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.wishlistItems) { item in
                        wishlistRow(item)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Wishlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddItem = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            addItemSheet
        }
        .refreshable {
            viewModel.loadWishlist()
        }
        .onAppear {
            viewModel.loadWishlist()
        }
    }

    // MARK: - Row

    private func wishlistRow(_ item: WishlistItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.statusIcon)
                .font(.title3)
                .foregroundColor(statusColor(item.status))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(item.status == "purchased" || item.status == "dropped")

                HStack(spacing: 8) {
                    Text(formatCurrency(item.estimatedCost, currency: item.currency))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    priorityBadge(item.priority)
                }
            }

            Spacer()

            if item.status == "wanted" {
                Menu {
                    Button(action: { Task { await viewModel.updateWishlistStatus(id: item.id, status: "saving") } }) {
                        Label("Start Saving", systemImage: "banknote")
                    }
                    Button(action: { Task { await viewModel.updateWishlistStatus(id: item.id, status: "purchased") } }) {
                        Label("Mark Purchased", systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive, action: { Task { await viewModel.updateWishlistStatus(id: item.id, status: "dropped") } }) {
                        Label("Drop", systemImage: "xmark.circle")
                    }
                    Divider()
                    Button(role: .destructive, action: { Task { await viewModel.deleteWishlistItem(id: item.id) } }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
            } else if item.status == "saving" {
                Menu {
                    Button(action: { Task { await viewModel.updateWishlistStatus(id: item.id, status: "purchased") } }) {
                        Label("Mark Purchased", systemImage: "checkmark.circle")
                    }
                    Button(action: { Task { await viewModel.updateWishlistStatus(id: item.id, status: "wanted") } }) {
                        Label("Back to Wanted", systemImage: "heart")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(12)
    }

    // MARK: - Add Item Sheet

    private var addItemSheet: some View {
        NavigationView {
            Form {
                TextField("Item Name", text: $newName)
                HStack {
                    Text("AED")
                        .foregroundColor(.secondary)
                    TextField("Estimated Cost", text: $newCost)
                        .keyboardType(.decimalPad)
                }
                Picker("Priority", selection: $newPriority) {
                    Text("High").tag(1)
                    Text("Medium").tag(3)
                    Text("Normal").tag(5)
                    Text("Low").tag(7)
                }
                TextField("URL (optional)", text: $newUrl)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                TextField("Notes (optional)", text: $newNotes, axis: .vertical)
                    .lineLimit(3)
            }
            .navigationTitle("Add to Wishlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingAddItem = false
                        clearForm()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        saveItem()
                    }
                    .disabled(newName.isEmpty || Double(newCost) == nil)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Wishlist Items")
                .font(.headline)
            Text("Track purchase goals and see when you can afford them.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showingAddItem = true }) {
                Label("Add Item", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func priorityBadge(_ priority: Int) -> some View {
        let label: String
        let color: Color
        switch priority {
        case 1: label = "P1"; color = .nexusError
        case 2...3: label = "P\(priority)"; color = .nexusWarning
        case 4...5: label = "P\(priority)"; color = .nexusFinance
        default: label = "P\(priority)"; color = .secondary
        }
        return Text(label)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "wanted": return .nexusMood
        case "saving": return .nexusWarning
        case "purchased": return .nexusSuccess
        case "dropped": return .gray
        default: return .secondary
        }
    }

    private func saveItem() {
        guard let cost = Double(newCost) else { return }
        let request = CreateWishlistRequest(
            name: newName,
            estimatedCost: cost,
            currency: "AED",
            priority: newPriority,
            targetDate: nil,
            url: newUrl.isEmpty ? nil : newUrl,
            notes: newNotes.isEmpty ? nil : newNotes
        )
        Task {
            let success = await viewModel.addWishlistItem(request)
            if success {
                showingAddItem = false
                clearForm()
            }
        }
    }

    private func clearForm() {
        newName = ""
        newCost = ""
        newPriority = 5
        newUrl = ""
        newNotes = ""
    }
}

#Preview {
    NavigationView {
        WishlistView(viewModel: FinanceViewModel())
    }
}
