import SwiftUI

/// View to display and manage permanently failed offline items
struct FailedItemsView: View {
    @ObservedObject private var queue = OfflineQueue.shared
    @State private var failedItems: [OfflineQueue.FailedEntry] = []
    @State private var showingClearAllAlert = false

    var body: some View {
        List {
            if failedItems.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("No failed items")
                            .font(.headline)
                        Text("All your data is synced successfully.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                Section {
                    ForEach(failedItems) { item in
                        FailedItemRow(item: item, onRetry: {
                            queue.retryFailedItem(id: item.id)
                            refreshItems()
                        }, onDiscard: {
                            queue.discardFailedItem(id: item.id)
                            refreshItems()
                        })
                    }
                } header: {
                    Text("\(failedItems.count) Failed Items")
                } footer: {
                    Text("These items failed to sync after multiple attempts. You can retry or discard them.")
                        .font(.caption)
                }

                Section {
                    Button(role: .destructive) {
                        showingClearAllAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Discard All Failed Items")
                        }
                    }
                } footer: {
                    Text("Warning: Discarding items means this data will be permanently lost.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Failed Items")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshItems() }
        .alert("Discard All Failed Items?", isPresented: $showingClearAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard All", role: .destructive) {
                queue.clearFailedItems()
                refreshItems()
            }
        } message: {
            Text("This will permanently delete \(failedItems.count) items that failed to sync. This cannot be undone.")
        }
    }

    private func refreshItems() {
        failedItems = queue.getFailedItems()
    }
}

struct FailedItemRow: View {
    let item: OfflineQueue.FailedEntry
    let onRetry: () -> Void
    let onDiscard: () -> Void

    @State private var showingActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForType)
                    .foregroundColor(.orange)
                Text(item.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            HStack {
                Text("Failed: \(item.failedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Text(item.lastError)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)

            HStack(spacing: 12) {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Button(role: .destructive) {
                    onDiscard()
                } label: {
                    Label("Discard", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private var iconForType: String {
        if item.type.contains("Food") { return "fork.knife" }
        if item.type.contains("Water") { return "drop.fill" }
        if item.type.contains("Weight") { return "scalemass" }
        if item.type.contains("Expense") || item.type.contains("Transaction") { return "creditcard" }
        if item.type.contains("Income") { return "banknote" }
        return "exclamationmark.circle"
    }
}

#Preview {
    NavigationView {
        FailedItemsView()
    }
}
