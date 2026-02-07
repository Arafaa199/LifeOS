import SwiftUI

// MARK: - Custom Tab Bar with Center FAB

struct ThemeTabBar: View {
    @Binding var selectedTab: Int
    let onFABTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab bar background
            HStack(spacing: 0) {
                // Left tabs
                tabItem(index: 0, icon: "house", activeIcon: "house.fill", label: "Home")
                tabItem(index: 1, icon: "heart", activeIcon: "heart.fill", label: "Health")

                // Center spacer for FAB
                Spacer()
                    .frame(width: 72)

                // Right tabs
                tabItem(index: 2, icon: "chart.pie", activeIcon: "chart.pie.fill", label: "Finance")
                tabItem(index: 3, icon: "calendar", activeIcon: "calendar.circle.fill", label: "Log")
            }
            .padding(.horizontal, NexusTheme.Spacing.md)
            .padding(.top, NexusTheme.Spacing.xs)
            .padding(.bottom, 20)
            .background(
                NexusTheme.Colors.navBar
                    .overlay(alignment: .top) {
                        NexusTheme.Colors.divider.frame(height: 1)
                    }
            )

            // Center FAB
            Button(action: {
                NexusTheme.Haptics.medium()
                onFABTap()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
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
            .offset(y: -20)
        }
    }

    @ViewBuilder
    private func tabItem(index: Int, icon: String, activeIcon: String, label: String) -> some View {
        Button(action: {
            NexusTheme.Haptics.selection()
            withAnimation(NexusTheme.Animation.quick) {
                selectedTab = index
            }
        }) {
            VStack(spacing: NexusTheme.Spacing.xxxs) {
                Image(systemName: selectedTab == index ? activeIcon : icon)
                    .font(.system(size: 22))
                    .frame(height: 24)

                NexusTheme.Typography.navLabel(label)
            }
            .foregroundColor(selectedTab == index ? NexusTheme.Colors.accent : NexusTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sidebar Drawer

struct ThemeSidebarDrawer: View {
    @Binding var isOpen: Bool
    @Binding var selectedTab: Int
    let onNavigate: (SidebarDestination) -> Void
    @Environment(\.colorScheme) private var colorScheme

    enum SidebarDestination: String, CaseIterable {
        case home = "Home"
        case health = "Health"
        case finance = "Finance"
        case calendar = "Calendar"
        case documents = "Documents"
        case music = "Music"
        case receipts = "Receipts"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .health: return "heart.fill"
            case .finance: return "chart.pie.fill"
            case .calendar: return "calendar"
            case .documents: return "doc.text.fill"
            case .music: return "music.note"
            case .receipts: return "receipt"
            case .settings: return "gearshape.fill"
            }
        }

        var isMainTab: Bool {
            switch self {
            case .home, .health, .finance, .calendar:
                return true
            default:
                return false
            }
        }

        var tabIndex: Int? {
            switch self {
            case .home: return 0
            case .health: return 1
            case .finance: return 2
            case .calendar: return 3
            default: return nil
            }
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Dimmed background
            if isOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeSidebar()
                    }
                    .transition(.opacity)
            }

            // Sidebar panel
            if isOpen {
                sidebarContent
                    .frame(width: 280)
                    .background(NexusTheme.Colors.card)
                    .offset(x: 0)
                    .transition(.move(edge: .leading))
            }
        }
        .animation(NexusTheme.Animation.smooth, value: isOpen)
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: NexusTheme.Spacing.xs) {
                HStack {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 32))
                        .foregroundColor(NexusTheme.Colors.accent)

                    Spacer()

                    Button(action: closeSidebar) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(NexusTheme.Colors.cardAlt)
                            .cornerRadius(8)
                    }
                }

                NexusTheme.Typography.pageTitle("Nexus")
                    .foregroundColor(NexusTheme.Colors.textPrimary)

                NexusTheme.Typography.caption("Life Operating System")
                    .foregroundColor(NexusTheme.Colors.textSecondary)
            }
            .padding(NexusTheme.Spacing.xl)
            .padding(.top, NexusTheme.Spacing.xxxl)

            Divider()
                .background(NexusTheme.Colors.divider)

            // Navigation items
            ScrollView {
                VStack(spacing: NexusTheme.Spacing.xs) {
                    // Main section
                    sectionHeader("Main")

                    ForEach(SidebarDestination.allCases.filter { $0.isMainTab }, id: \.rawValue) { dest in
                        sidebarItem(dest, isActive: dest.tabIndex == selectedTab)
                    }

                    // More section
                    sectionHeader("More")
                        .padding(.top, NexusTheme.Spacing.lg)

                    ForEach(SidebarDestination.allCases.filter { !$0.isMainTab }, id: \.rawValue) { dest in
                        sidebarItem(dest, isActive: false)
                    }
                }
                .padding(NexusTheme.Spacing.lg)
            }

            Spacer()

            // Footer
            Divider()
                .background(NexusTheme.Colors.divider)

            HStack {
                NexusTheme.Typography.caption("v2.0")
                    .foregroundColor(NexusTheme.Colors.textMuted)

                Spacer()

                NexusTheme.Typography.caption("Design System v2")
                    .foregroundColor(NexusTheme.Colors.textMuted)
            }
            .padding(NexusTheme.Spacing.lg)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        NexusTheme.Typography.badge(title)
            .foregroundColor(NexusTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NexusTheme.Spacing.lg)
            .padding(.top, NexusTheme.Spacing.xs)
    }

    @ViewBuilder
    private func sidebarItem(_ destination: SidebarDestination, isActive: Bool) -> some View {
        Button(action: {
            NexusTheme.Haptics.light()
            onNavigate(destination)
            closeSidebar()
        }) {
            HStack(spacing: NexusTheme.Spacing.md) {
                Image(systemName: destination.icon)
                    .font(.system(size: 18))
                    .frame(width: 20)

                Text(destination.rawValue)
                    .font(.system(size: 13, weight: .medium))

                Spacer()
            }
            .foregroundColor(isActive ? .white : NexusTheme.Colors.textPrimary)
            .padding(.horizontal, NexusTheme.Spacing.lg)
            .padding(.vertical, NexusTheme.Spacing.md)
            .background(isActive ? NexusTheme.Colors.accent : NexusTheme.Colors.cardAlt)
            .cornerRadius(NexusTheme.Radius.md)
        }
        .buttonStyle(.plain)
    }

    private func closeSidebar() {
        NexusTheme.Haptics.light()
        withAnimation(NexusTheme.Animation.smooth) {
            isOpen = false
        }
    }
}

// MARK: - Quick Log Sheet (FAB Action)

struct ThemeQuickLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAction: (QuickLogAction) -> Void

    enum QuickLogAction: CaseIterable {
        case water
        case food
        case mood
        case expense
        case note
        case fasting

        var icon: String {
            switch self {
            case .water: return "drop.fill"
            case .food: return "fork.knife"
            case .mood: return "face.smiling"
            case .expense: return "dollarsign.circle.fill"
            case .note: return "note.text"
            case .fasting: return "timer"
            }
        }

        var title: String {
            switch self {
            case .water: return "Water"
            case .food: return "Food"
            case .mood: return "Mood"
            case .expense: return "Expense"
            case .note: return "Note"
            case .fasting: return "Fasting"
            }
        }

        var color: Color {
            switch self {
            case .water: return NexusTheme.Colors.Semantic.blue
            case .food: return NexusTheme.Colors.Semantic.green
            case .mood: return NexusTheme.Colors.Semantic.amber
            case .expense: return NexusTheme.Colors.Semantic.purple
            case .note: return NexusTheme.Colors.textSecondary
            case .fasting: return NexusTheme.Colors.accent
            }
        }
    }

    var body: some View {
        VStack(spacing: NexusTheme.Spacing.lg) {
            // Handle indicator
            Capsule()
                .fill(NexusTheme.Colors.divider)
                .frame(width: 36, height: 5)
                .padding(.top, NexusTheme.Spacing.md)

            // Title
            HStack {
                NexusTheme.Typography.cardTitle("Quick Log")
                    .foregroundColor(NexusTheme.Colors.textSecondary)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(NexusTheme.Colors.textTertiary)
                }
            }
            .padding(.horizontal, NexusTheme.Spacing.xl)

            // Action grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: NexusTheme.Spacing.sm),
                GridItem(.flexible(), spacing: NexusTheme.Spacing.sm),
                GridItem(.flexible(), spacing: NexusTheme.Spacing.sm)
            ], spacing: NexusTheme.Spacing.sm) {
                ForEach(QuickLogAction.allCases, id: \.title) { action in
                    quickLogButton(action)
                }
            }
            .padding(.horizontal, NexusTheme.Spacing.xl)
            .padding(.bottom, NexusTheme.Spacing.xxxl)
        }
        .background(NexusTheme.Colors.card)
        .cornerRadius(NexusTheme.Radius.sheet, corners: [.topLeft, .topRight])
    }

    @ViewBuilder
    private func quickLogButton(_ action: QuickLogAction) -> some View {
        Button(action: {
            NexusTheme.Haptics.light()
            onAction(action)
            dismiss()
        }) {
            VStack(spacing: NexusTheme.Spacing.xs) {
                ZStack {
                    Circle()
                        .fill(action.color.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: action.icon)
                        .font(.system(size: 24))
                        .foregroundColor(action.color)
                }

                NexusTheme.Typography.caption(action.title)
                    .foregroundColor(NexusTheme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NexusTheme.Spacing.md)
            .background(NexusTheme.Colors.cardAlt)
            .cornerRadius(NexusTheme.Radius.xxl)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Page Header with Menu Button

struct ThemePageHeader: View {
    let title: String
    let subtitle: String?
    let onMenuTap: () -> Void
    let trailingContent: AnyView?

    init(
        _ title: String,
        subtitle: String? = nil,
        onMenuTap: @escaping () -> Void,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onMenuTap = onMenuTap
        self.trailingContent = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .center, spacing: NexusTheme.Spacing.md) {
            // Menu button
            Button(action: {
                NexusTheme.Haptics.light()
                onMenuTap()
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(NexusTheme.Colors.cardAlt)
                    .cornerRadius(NexusTheme.Radius.md)
            }

            // Title section
            VStack(alignment: .leading, spacing: 2) {
                NexusTheme.Typography.pageTitle(title)
                    .foregroundColor(NexusTheme.Colors.textPrimary)

                if let subtitle = subtitle {
                    NexusTheme.Typography.caption(subtitle)
                        .foregroundColor(NexusTheme.Colors.textSecondary)
                }
            }

            Spacer()

            // Trailing content
            trailingContent
        }
        .padding(.horizontal, NexusTheme.Spacing.xl)
        .padding(.vertical, NexusTheme.Spacing.md)
    }
}

// MARK: - Corner Radius Extension for Specific Corners

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview

#Preview("Tab Bar") {
    VStack {
        Spacer()
        ThemeTabBar(selectedTab: .constant(0)) {
            print("FAB tapped")
        }
    }
    .background(NexusTheme.Colors.background)
}

#Preview("Sidebar") {
    ZStack {
        Color.gray
        ThemeSidebarDrawer(
            isOpen: .constant(true),
            selectedTab: .constant(0)
        ) { destination in
            print("Navigate to \(destination)")
        }
    }
}

#Preview("Quick Log Sheet") {
    ThemeQuickLogSheet { action in
        print("Action: \(action)")
    }
}

#Preview("Page Header") {
    VStack {
        ThemePageHeader("Today", subtitle: "Friday, Feb 7") {
            print("Menu tapped")
        } trailing: {
            Image(systemName: "bell.badge")
                .foregroundColor(NexusTheme.Colors.accent)
        }
        Spacer()
    }
    .background(NexusTheme.Colors.background)
}
