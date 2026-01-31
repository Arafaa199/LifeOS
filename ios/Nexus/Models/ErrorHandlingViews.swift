import SwiftUI

// MARK: - Error Handling Views and Modifiers

/// View modifier that provides standardized error handling UI
struct ErrorHandlingModifier: ViewModifier {
    @Binding var error: NexusError?
    let onRetry: (() -> Void)?
    
    init(error: Binding<NexusError?>, onRetry: (() -> Void)? = nil) {
        self._error = error
        self.onRetry = onRetry
    }
    
    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                if error?.isRecoverable == true, let retry = onRetry {
                    Button("Retry") {
                        retry()
                    }
                }
                Button("OK", role: .cancel) {
                    error = nil
                }
            } message: {
                if let error = error {
                    VStack(alignment: .leading, spacing: 8) {
                        if let description = error.errorDescription {
                            Text(description)
                        }
                        if let suggestion = error.recoverySuggestion {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
    }
}

extension View {
    /// Adds error handling with retry capability
    ///
    /// - Parameters:
    ///   - error: Binding to optional NexusError
    ///   - onRetry: Optional closure to execute when user taps retry
    /// - Returns: View with error alert attached
    ///
    /// ## Example
    /// ```swift
    /// .handleError($viewModel.error) {
    ///     Task { await viewModel.loadData() }
    /// }
    /// ```
    func handleError(_ error: Binding<NexusError?>, onRetry: (() -> Void)? = nil) -> some View {
        modifier(ErrorHandlingModifier(error: error, onRetry: onRetry))
    }
}

// MARK: - Inline Error View

/// Displays an error message inline with optional retry button
struct InlineErrorView: View {
    let error: NexusError
    let onRetry: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.large)
                
                VStack(alignment: .leading, spacing: 4) {
                    if let description = error.errorDescription {
                        Text(description)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            
            if error.isRecoverable, let retry = onRetry {
                Button(action: retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Offline Indicator Banner

/// Banner that shows offline status and queued items
struct OfflineBannerView: View {
    @ObservedObject var networkMonitor = NetworkMonitor.shared
    @State private var queueCount: Int = 0
    
    var body: some View {
        if !networkMonitor.isConnected {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline Mode")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if queueCount > 0 {
                        Text("\(queueCount) items queued for sync")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Changes will sync when connected")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
            .task {
                await updateQueueCount()
            }
        }
    }
    
    private func updateQueueCount() async {
        queueCount = await OfflineQueue.shared.getQueueCount()
    }
}

// MARK: - Loading State View

/// View that shows loading state with optional cancellation
struct LoadingStateView: View {
    let message: String
    let onCancel: (() -> Void)?
    
    init(_ message: String = "Loading...", onCancel: (() -> Void)? = nil) {
        self.message = message
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if let cancel = onCancel {
                Button("Cancel", action: cancel)
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Empty State View

/// Generic empty state view for when there's no data
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Success Toast

/// Toast notification for success messages
struct SuccessToast: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
            
            Text(message)
                .font(.subheadline)
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let duration: TimeInterval
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                VStack {
                    Spacer()
                    SuccessToast(message: message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                withAnimation {
                                    isPresented = false
                                }
                            }
                        }
                }
                .padding(.bottom)
            }
        }
    }
}

extension View {
    /// Shows a success toast notification
    ///
    /// - Parameters:
    ///   - isPresented: Binding to control toast visibility
    ///   - message: Success message to display
    ///   - duration: How long to show the toast (default: 2 seconds)
    /// - Returns: View with toast overlay
    ///
    /// ## Example
    /// ```swift
    /// .toast(isPresented: $showSuccess, message: "Saved successfully!")
    /// ```
    func toast(isPresented: Binding<Bool>, message: String, duration: TimeInterval = 2.0) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, duration: duration))
    }
}

// MARK: - Preview Helpers

#Preview("Error Alert") {
    struct PreviewWrapper: View {
        @State private var error: NexusError? = .network(URLError(.notConnectedToInternet))
        
        var body: some View {
            VStack {
                Button("Show Error") {
                    error = .offline(queuedItemCount: 5)
                }
            }
            .handleError($error) {
                print("Retry tapped")
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Inline Error") {
    InlineErrorView(
        error: .api(.serverError(500)),
        onRetry: { print("Retry") }
    )
}

#Preview("Offline Banner") {
    VStack {
        OfflineBannerView()
        Spacer()
    }
}

#Preview("Loading State") {
    LoadingStateView("Loading your data...") {
        print("Cancelled")
    }
}

#Preview("Empty State") {
    EmptyStateView(
        icon: "tray.fill",
        title: "No Transactions",
        message: "Start tracking your finances by adding your first transaction",
        actionTitle: "Add Transaction"
    ) {
        print("Action tapped")
    }
}
