import SwiftUI

// MARK: - Theme Components
// Complete component library for the Nexus design system v2

// MARK: - Buttons

/// Primary action button with accent background
struct ThemePrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: {
            NexusTheme.Haptics.light()
            action()
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background(isDisabled ? NexusTheme.Colors.accent.opacity(0.5) : NexusTheme.Colors.accent)
            .cornerRadius(NexusTheme.Radius.md)
            .shadow(
                color: isDisabled ? .clear : NexusTheme.Shadow.button.color,
                radius: NexusTheme.Shadow.button.radius,
                y: NexusTheme.Shadow.button.y
            )
        }
        .disabled(isDisabled || isLoading)
    }
}

/// Secondary button with border
struct ThemeSecondaryButton: View {
    let title: String
    let icon: String?
    let isDisabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: {
            NexusTheme.Haptics.light()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isDisabled ? NexusTheme.Colors.accent.opacity(0.5) : NexusTheme.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.md)
                    .stroke(isDisabled ? NexusTheme.Colors.accent.opacity(0.3) : NexusTheme.Colors.accent, lineWidth: 1.5)
            )
        }
        .disabled(isDisabled)
    }
}

/// Icon-only button
struct ThemeIconButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void

    init(_ icon: String, size: CGFloat = 44, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: {
            NexusTheme.Haptics.light()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(NexusTheme.Colors.textPrimary)
                .frame(width: size, height: size)
                .background(NexusTheme.Colors.cardAlt)
                .cornerRadius(NexusTheme.Radius.md)
        }
    }
}

/// Floating Action Button (FAB)
struct ThemeFAB: View {
    let icon: String
    let action: () -> Void

    init(_ icon: String = "plus", action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: {
            NexusTheme.Haptics.medium()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(NexusTheme.Colors.accent)
                .cornerRadius(NexusTheme.Radius.xl)
                .shadow(
                    color: NexusTheme.Shadow.fab.color,
                    radius: NexusTheme.Shadow.fab.radius,
                    y: NexusTheme.Shadow.fab.y
                )
        }
    }
}

// MARK: - Cards

/// Standard card container
struct ThemeCard<Content: View>: View {
    let content: Content
    var elevated: Bool = false

    init(elevated: Bool = false, @ViewBuilder content: () -> Content) {
        self.elevated = elevated
        self.content = content()
    }

    var body: some View {
        content
            .padding(NexusTheme.Spacing.lg)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
            .shadow(
                color: elevated ? NexusTheme.Shadow.cardElevated.color : NexusTheme.Shadow.card.color,
                radius: elevated ? NexusTheme.Shadow.cardElevated.radius : NexusTheme.Shadow.card.radius,
                y: elevated ? NexusTheme.Shadow.cardElevated.y : NexusTheme.Shadow.card.y
            )
    }
}

/// Card with title header
struct ThemeTitledCard<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ThemeCard {
            VStack(alignment: .leading, spacing: NexusTheme.Spacing.md) {
                NexusTheme.Typography.cardTitle(title)
                    .foregroundColor(NexusTheme.Colors.textTertiary)
                content
            }
        }
    }
}

/// Alert/Warning banner
struct ThemeAlertBanner: View {
    let message: String
    let icon: String
    var type: AlertType = .warning

    enum AlertType {
        case info, warning, error, success

        var color: Color {
            switch self {
            case .info: return NexusTheme.Colors.Semantic.blue
            case .warning: return NexusTheme.Colors.Semantic.amber
            case .error: return NexusTheme.Colors.Semantic.red
            case .success: return NexusTheme.Colors.Semantic.green
            }
        }
    }

    var body: some View {
        HStack(spacing: NexusTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(type.color)
                .cornerRadius(4)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(NexusTheme.Colors.textPrimary)
                .lineLimit(2)
        }
        .padding(NexusTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(type.color.opacity(0.10))
        .cornerRadius(NexusTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.md)
                .stroke(type.color.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Metric Tile

/// Compact metric display tile
struct ThemeMetricTile: View {
    let label: String
    let value: String
    let unit: String?
    var color: Color = NexusTheme.Colors.accent

    var body: some View {
        VStack(spacing: NexusTheme.Spacing.xs) {
            NexusTheme.Typography.metricLabel(label)
                .foregroundColor(NexusTheme.Colors.textTertiary)

            NexusTheme.Typography.metricValue(value)
                .foregroundColor(NexusTheme.Colors.textPrimary)

            if let unit = unit {
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.xxl)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.xxl)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }
}

// MARK: - Badges

/// Status badge with background
struct ThemeBadge: View {
    let text: String
    var color: Color = NexusTheme.Colors.accent
    var size: BadgeSize = .regular

    enum BadgeSize {
        case small, regular

        var padding: (h: CGFloat, v: CGFloat) {
            switch self {
            case .small: return (8, 4)
            case .regular: return (12, 6)
            }
        }
    }

    var body: some View {
        NexusTheme.Typography.badge(text)
            .foregroundColor(.white)
            .padding(.horizontal, size.padding.h)
            .padding(.vertical, size.padding.v)
            .background(color)
            .cornerRadius(NexusTheme.Radius.xs)
    }
}

/// Soft-colored chip
struct ThemeChip: View {
    let text: String
    var color: Color = NexusTheme.Colors.accent
    var isSelected: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? color : color.opacity(0.12))
            .cornerRadius(20)
    }
}

// MARK: - Progress Indicators

/// Horizontal progress bar
struct ThemeProgressBar: View {
    let progress: Double // 0.0 to 1.0
    var color: Color = NexusTheme.Colors.accent
    var height: CGFloat = 6
    var showGradient: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(NexusTheme.Colors.divider)
                    .frame(height: height)

                // Fill
                Capsule()
                    .fill(
                        showGradient
                            ? LinearGradient(
                                colors: [color, color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(colors: [color], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * min(max(progress, 0), 1), height: height)
            }
        }
        .frame(height: height)
    }
}

/// Circular progress ring
struct ThemeProgressRing: View {
    let progress: Double // 0.0 to 1.0
    var color: Color = NexusTheme.Colors.accent
    var lineWidth: CGFloat = 8
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(NexusTheme.Colors.divider, lineWidth: lineWidth)

            // Progress
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.5), value: progress)
        }
        .frame(width: size, height: size)
    }
}

/// Fasting-style timer ring with center content
struct ThemeTimerRing<Content: View>: View {
    let progress: Double
    var color: Color = NexusTheme.Colors.accent
    var size: CGFloat = 160
    let content: Content

    init(
        progress: Double,
        color: Color = NexusTheme.Colors.accent,
        size: CGFloat = 160,
        @ViewBuilder content: () -> Content
    ) {
        self.progress = progress
        self.color = color
        self.size = size
        self.content = content()
    }

    var body: some View {
        ZStack {
            // Outer ring
            ThemeProgressRing(progress: progress, color: color, lineWidth: 8, size: size)

            // Inner content area
            Circle()
                .fill(NexusTheme.Colors.card)
                .frame(width: size - 20, height: size - 20)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)

            content
        }
    }
}

// MARK: - Form Elements

/// Styled text input
struct ThemeTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: NexusTheme.Spacing.md) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
            }

            TextField(placeholder, text: $text)
                .font(.system(size: 13))
                .foregroundColor(NexusTheme.Colors.textPrimary)
        }
        .padding(NexusTheme.Spacing.md)
        .background(NexusTheme.Colors.cardAlt)
        .cornerRadius(NexusTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.md)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }
}

/// Period selector tabs (7D / 30D / 90D style)
struct ThemeSegmentedControl<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button(action: {
                    NexusTheme.Haptics.selection()
                    withAnimation(NexusTheme.Animation.quick) {
                        selection = option
                    }
                }) {
                    Text(label(option))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selection == option ? .white : NexusTheme.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selection == option ? NexusTheme.Colors.accent : NexusTheme.Colors.cardAlt)
                }
            }
        }
        .cornerRadius(NexusTheme.Radius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: NexusTheme.Radius.sm)
                .stroke(NexusTheme.Colors.divider, lineWidth: 1)
        )
    }
}

/// Toggle switch with label
struct ThemeToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(NexusTheme.Colors.textPrimary)

            Spacer()

            Toggle("", isOn: $isOn)
                .tint(NexusTheme.Colors.accent)
                .labelsHidden()
        }
        .padding(NexusTheme.Spacing.lg)
        .background(NexusTheme.Colors.cardAlt)
        .cornerRadius(NexusTheme.Radius.md)
    }
}

// MARK: - List Items

/// Standard list item row
struct ThemeListItem: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    var value: String? = nil
    var showChevron: Bool = true

    var body: some View {
        HStack(spacing: NexusTheme.Spacing.md) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 44, height: 44)
                .background(iconColor.opacity(0.12))
                .cornerRadius(NexusTheme.Radius.md)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(NexusTheme.Colors.textTertiary)
                }
            }

            Spacer()

            if let value = value {
                Text(value)
                    .font(.system(size: 12))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textMuted)
            }
        }
        .padding(.vertical, NexusTheme.Spacing.md)
    }
}

/// Transaction row
struct ThemeTransactionRow: View {
    let icon: String
    let iconColor: Color
    let merchant: String
    let category: String
    let amount: String
    let date: String
    var isIncome: Bool = false

    var body: some View {
        HStack(spacing: NexusTheme.Spacing.md) {
            // Icon
            Text(icon)
                .font(.system(size: 18))
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.15))
                .cornerRadius(NexusTheme.Radius.sm)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(merchant)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textPrimary)

                Text(category)
                    .font(.system(size: 11))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
            }

            Spacer()

            // Amount & Date
            VStack(alignment: .trailing, spacing: 2) {
                Text(amount)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isIncome ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.accent)

                Text(date)
                    .font(.system(size: 11))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
            }
        }
        .padding(.vertical, NexusTheme.Spacing.md)
    }
}

// MARK: - Quick Log Grid

/// Quick action button for log sheet
struct ThemeQuickLogButton: View {
    let emoji: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            NexusTheme.Haptics.light()
            action()
        }) {
            VStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 24))

                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(NexusTheme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(NexusTheme.Colors.cardAlt)
            .cornerRadius(NexusTheme.Radius.lg)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State

/// Full empty state with illustration, headline, and CTA
struct ThemeEmptyState: View {
    let icon: String
    let headline: String
    let description: String
    var ctaTitle: String? = nil
    var ctaAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: NexusTheme.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(NexusTheme.Colors.accent.opacity(0.6))
                .padding(.bottom, NexusTheme.Spacing.md)

            Text(headline)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(NexusTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(description)
                .font(.system(size: 15))
                .foregroundColor(NexusTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, NexusTheme.Spacing.xxl)

            if let title = ctaTitle, let action = ctaAction {
                ThemePrimaryButton(title, action: action)
                    .frame(width: 200)
                    .padding(.top, NexusTheme.Spacing.md)
            }
        }
        .padding(NexusTheme.Spacing.xxxl)
    }
}

// MARK: - Loading State

/// Skeleton loading placeholder
struct ThemeSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 20
    var cornerRadius: CGFloat = 8

    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        NexusTheme.Colors.cardAlt,
                        NexusTheme.Colors.card,
                        NexusTheme.Colors.cardAlt
                    ],
                    startPoint: isAnimating ? .trailing : .leading,
                    endPoint: isAnimating ? .leading : .trailing
                )
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

/// Loading spinner with message
struct ThemeLoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: NexusTheme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(NexusTheme.Colors.accent)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(NexusTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Theme Components") {
    ScrollView {
        VStack(spacing: 24) {
            // Buttons
            Group {
                Text("Buttons").font(.headline)
                ThemePrimaryButton("Primary Button") {}
                ThemePrimaryButton("With Icon", icon: "plus") {}
                ThemePrimaryButton("Disabled", isDisabled: true) {}
                ThemeSecondaryButton("Secondary Button") {}
                HStack {
                    ThemeIconButton("arrow.left") {}
                    ThemeIconButton("gearshape") {}
                    ThemeIconButton("xmark") {}
                    Spacer()
                    ThemeFAB {}
                }
            }

            Divider()

            // Cards
            Group {
                Text("Cards").font(.headline)
                ThemeCard {
                    Text("Standard Card Content")
                }
                ThemeTitledCard("Performance") {
                    Text("Your metrics are tracking well.")
                        .foregroundColor(NexusTheme.Colors.textSecondary)
                }
                ThemeAlertBanner(message: "You've been inactive for 4 hours.", icon: "exclamationmark", type: .warning)
            }

            Divider()

            // Metrics
            Group {
                Text("Metrics").font(.headline)
                HStack(spacing: 10) {
                    ThemeMetricTile(label: "Steps", value: "8,240", unit: "Today")
                    ThemeMetricTile(label: "Calories", value: "2,180", unit: "Burned")
                }
            }

            Divider()

            // Badges
            Group {
                Text("Badges").font(.headline)
                HStack {
                    ThemeBadge(text: "New")
                    ThemeBadge(text: "Active", color: .themeGreen)
                    ThemeBadge(text: "Warning", color: .themeAmber)
                    ThemeBadge(text: "Critical", color: .themeRed)
                }
            }

            Divider()

            // Progress
            Group {
                Text("Progress").font(.headline)
                ThemeProgressBar(progress: 0.65)
                HStack {
                    ThemeProgressRing(progress: 0.75, size: 80)
                    Spacer()
                    ThemeTimerRing(progress: 0.875, size: 100) {
                        VStack(spacing: 2) {
                            Text("14h")
                                .font(.system(size: 20, weight: .black))
                            Text("of 16h")
                                .font(.system(size: 10))
                                .foregroundColor(NexusTheme.Colors.textTertiary)
                        }
                    }
                }
            }

            Divider()

            // Form Elements
            Group {
                Text("Form Elements").font(.headline)
                ThemeTextField(placeholder: "Enter value...", text: .constant(""), icon: "magnifyingglass")
            }
        }
        .padding()
    }
    .background(NexusTheme.Colors.background)
}
