import SwiftUI

/// Shows pending/failed sync items from offline queue
struct SyncIssuesSection: View {
    @ObservedObject var offlineQueue: OfflineQueue

    var body: some View {
        let failedCount = offlineQueue.failedItemCount
        let pendingCount = offlineQueue.pendingItemCount

        Group {
            if failedCount > 0 || pendingCount > 0 {
                Section {
                    if pendingCount > 0 {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.orange)
                            Text("\(pendingCount) items pending sync")
                            Spacer()
                            if !NetworkMonitor.shared.isConnected {
                                Text("Offline")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if failedCount > 0 {
                        NavigationLink {
                            FailedItemsView()
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("\(failedCount) items failed to sync")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                } header: {
                    Text("Sync Issues")
                } footer: {
                    if failedCount > 0 {
                        Text("Failed items need attention. Tap to review and retry or discard.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
