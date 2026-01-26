import SwiftUI

// MARK: - Nexus Brand Colors

extension Color {
    // Primary brand color - a vibrant teal/cyan
    static let nexusPrimary = Color(red: 0.0, green: 0.71, blue: 0.76) // #00B5C2
    static let nexusPrimaryDark = Color(red: 0.0, green: 0.55, blue: 0.59) // #008C96
    static let nexusPrimaryLight = Color(red: 0.4, green: 0.85, blue: 0.89) // #66D9E3

    // Secondary accent - warm coral for actions
    static let nexusAccent = Color(red: 1.0, green: 0.45, blue: 0.38) // #FF7361
    static let nexusAccentLight = Color(red: 1.0, green: 0.65, blue: 0.58) // #FFA695

    // Category colors (refined)
    static let nexusFood = Color(red: 1.0, green: 0.58, blue: 0.0) // #FF9500
    static let nexusWater = Color(red: 0.0, green: 0.64, blue: 0.91) // #00A3E8
    static let nexusWeight = Color(red: 0.2, green: 0.78, blue: 0.35) // #33C759
    static let nexusMood = Color(red: 0.69, green: 0.32, blue: 0.87) // #B052DE
    static let nexusProtein = Color(red: 0.96, green: 0.26, blue: 0.21) // #F54336
    static let nexusFinance = Color(red: 0.13, green: 0.59, blue: 0.95) // #2196F3
    static let nexusHealth = Color(red: 0.2, green: 0.78, blue: 0.35) // #33C759 - same as success/weight

    // Semantic colors
    static let nexusSuccess = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let nexusWarning = Color(red: 1.0, green: 0.76, blue: 0.03)
    static let nexusError = Color(red: 0.96, green: 0.26, blue: 0.21)

    // Background variants
    static let nexusCardBackground = Color(.systemGray6)
    static let nexusCardBackgroundElevated = Color(.systemGray5)
}

// MARK: - Gradients

extension LinearGradient {
    static let nexusPrimaryGradient = LinearGradient(
        colors: [Color.nexusPrimary, Color.nexusPrimaryDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let nexusAccentGradient = LinearGradient(
        colors: [Color.nexusAccent, Color.nexusAccentLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let nexusHealthGradient = LinearGradient(
        colors: [Color.nexusFood.opacity(0.8), Color.nexusProtein.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let nexusFinanceGradient = LinearGradient(
        colors: [Color.nexusFinance, Color.nexusPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Custom View Modifiers

struct NexusCardStyle: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding()
            .background(elevated ? Color.nexusCardBackgroundElevated : Color.nexusCardBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(elevated ? 0.1 : 0.05), radius: elevated ? 8 : 4, x: 0, y: 2)
    }
}

struct NexusGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

struct NexusPrimaryButton: ViewModifier {
    var isDisabled: Bool = false

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isDisabled ? Color.gray : Color.nexusPrimary)
            .cornerRadius(14)
            .shadow(color: Color.nexusPrimary.opacity(isDisabled ? 0 : 0.3), radius: 8, x: 0, y: 4)
    }
}

struct NexusSecondaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.nexusPrimary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.nexusPrimary.opacity(0.12))
            .cornerRadius(14)
    }
}

struct NexusAccentButton: ViewModifier {
    var isDisabled: Bool = false

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isDisabled ? Color.gray : Color.nexusAccent)
            .cornerRadius(14)
            .shadow(color: Color.nexusAccent.opacity(isDisabled ? 0 : 0.3), radius: 8, x: 0, y: 4)
    }
}

struct NexusChip: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(20)
    }
}

struct NexusTextField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.nexusPrimary.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - View Extensions

extension View {
    func nexusCard(elevated: Bool = false) -> some View {
        modifier(NexusCardStyle(elevated: elevated))
    }

    func nexusGlassCard() -> some View {
        modifier(NexusGlassCard())
    }

    func nexusPrimaryButton(disabled: Bool = false) -> some View {
        modifier(NexusPrimaryButton(isDisabled: disabled))
    }

    func nexusSecondaryButton() -> some View {
        modifier(NexusSecondaryButton())
    }

    func nexusAccentButton(disabled: Bool = false) -> some View {
        modifier(NexusAccentButton(isDisabled: disabled))
    }

    func nexusChip(color: Color) -> some View {
        modifier(NexusChip(color: color))
    }

    func nexusTextField() -> some View {
        modifier(NexusTextField())
    }
}

// MARK: - Reusable Components

struct NexusIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 24
    var background: Bool = true

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.6, weight: .semibold))
            .foregroundColor(background ? color : color)
            .frame(width: size, height: size)
            .background(
                background ?
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: size * 1.6, height: size * 1.6)
                : nil
            )
    }
}

struct NexusHeaderView: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let color: Color

    init(_ title: String, subtitle: String? = nil, icon: String? = nil, color: Color = .nexusPrimary) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                NexusIcon(systemName: icon, color: color, size: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }
}

struct NexusStatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var trend: Double? = nil
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.8), color],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .symbolEffect(.pulse, isActive: isLoading)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .redacted(reason: isLoading ? .placeholder : [])

                    Text(unit)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Trend indicator
            if let trend = trend {
                HStack(spacing: 2) {
                    Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption)
                    Text(String(format: "%.1f%%", abs(trend)))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(trend >= 0 ? .nexusSuccess : .nexusError)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((trend >= 0 ? Color.nexusSuccess : Color.nexusError).opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

struct NexusEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .nexusSecondaryButton()
                .frame(width: 200)
            }
        }
        .padding(32)
    }
}

struct NexusQuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(color)
                }

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(minWidth: 80)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color.nexusCardBackground)
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct NexusSegmentedPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let titleForOption: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button(action: { selection = option }) {
                    Text(titleForOption(option))
                        .font(.subheadline)
                        .fontWeight(selection == option ? .semibold : .regular)
                        .foregroundColor(selection == option ? .white : .primary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            selection == option ?
                            Color.nexusPrimary : Color.clear
                        )
                }
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Loading States

struct NexusLoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.nexusPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NexusRefreshIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.nexusPrimary)
            Text("Syncing...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Status Badge

struct NexusStatusBadge: View {
    enum Status {
        case online, offline, syncing, error

        var color: Color {
            switch self {
            case .online: return .nexusSuccess
            case .offline: return .nexusWarning
            case .syncing: return .nexusPrimary
            case .error: return .nexusError
            }
        }

        var icon: String {
            switch self {
            case .online: return "wifi"
            case .offline: return "wifi.slash"
            case .syncing: return "arrow.triangle.2.circlepath"
            case .error: return "exclamationmark.triangle"
            }
        }

        var label: String {
            switch self {
            case .online: return "Online"
            case .offline: return "Offline"
            case .syncing: return "Syncing"
            case .error: return "Error"
            }
        }
    }

    let status: Status

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption2)
                .symbolEffect(.pulse, isActive: status == .syncing)

            Text(status.label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.12))
        .cornerRadius(8)
    }
}

// MARK: - Animated Number

struct AnimatedNumber: View {
    let value: Double
    let format: String

    @State private var displayedValue: Double = 0

    var body: some View {
        Text(String(format: format, displayedValue))
            .contentTransition(.numericText())
            .onAppear {
                withAnimation(.spring(duration: 0.8)) {
                    displayedValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.spring(duration: 0.5)) {
                    displayedValue = newValue
                }
            }
    }
}
