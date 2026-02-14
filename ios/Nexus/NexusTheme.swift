import SwiftUI
import UIKit

// MARK: - Nexus Design System v2
// Complete redesign based on the Nexus iOS Design System specification
// Warm, sophisticated color palette with Inter typography

// MARK: - Theme Namespace

enum NexusTheme {
    // MARK: - Color Palette

    enum Colors {
        // MARK: Accent (Same in both modes)
        static let accent = Color(hex: "FF005E")
        static let accentSoft = Color(hex: "FF005E").opacity(0.10)

        // MARK: Light Mode Backgrounds
        enum Light {
            static let background = Color(hex: "E4D5C3")
            static let card = Color(hex: "F5EDE3")
            static let cardAlt = Color(hex: "EDE3D6")
            static let navBar = Color(hex: "F4ECE4").opacity(0.92)
            static let divider = Color.black.opacity(0.06)
        }

        // MARK: Dark Mode Backgrounds
        enum Dark {
            static let background = Color(hex: "141210")
            static let card = Color(hex: "1E1C18")
            static let cardAlt = Color(hex: "262320")
            static let navBar = Color(hex: "141210").opacity(0.92)
            static let divider = Color.white.opacity(0.05)
        }

        // MARK: Light Mode Text
        enum LightText {
            static let primary = Color(hex: "1A1410")
            static let secondary = Color(hex: "6B5D4F")
            static let tertiary = Color(hex: "9B8C7C")
            static let muted = Color(hex: "B5A594")
        }

        // MARK: Dark Mode Text
        enum DarkText {
            static let primary = Color(hex: "F2EDE8")
            static let secondary = Color(hex: "B0A898")
            static let tertiary = Color(hex: "7A7068")
            static let muted = Color(hex: "504840")
        }

        // MARK: Semantic Colors (Mode-Adaptive)
        enum Semantic {
            static let green = Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: "00C07B")
                    : UIColor(hex: "00A86B")
            })

            static let blue = Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: "3D9AE8")
                    : UIColor(hex: "2E86DE")
            })

            static let amber = Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: "F0943D")
                    : UIColor(hex: "E67E22")
            })

            static let purple = Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: "9B6AE8")
                    : UIColor(hex: "8854D0")
            })

            static let red = Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: "F05545")
                    : UIColor(hex: "E74C3C")
            })
        }

        // MARK: Adaptive Colors (Auto-switch based on color scheme)

        static let background = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: "141210")
                : UIColor(hex: "E4D5C3")
        })

        static let card = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: "1E1C18")
                : UIColor(hex: "F5EDE3")
        })

        static let cardAlt = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: "262320")
                : UIColor(hex: "EDE3D6")
        })

        static let navBar = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: "141210").withAlphaComponent(0.92)
                : UIColor(hex: "F4ECE4").withAlphaComponent(0.92)
        })

        static let divider = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.05)
                : UIColor.black.withAlphaComponent(0.06)
        })

        static let textPrimary = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: "F2EDE8")
                : UIColor(hex: "1A1410")
        })

        static let textSecondary = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: "B0A898")
                : UIColor(hex: "6B5D4F")
        })

        static let textTertiary = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: "7A7068")
                : UIColor(hex: "9B8C7C")
        })

        static let textMuted = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: "504840")
                : UIColor(hex: "B5A594")
        })
    }

    // MARK: - Typography

    enum Typography {
        // Page Title: 26-28px, weight 900, tracking -0.8px
        static func pageTitle(_ text: String) -> Text {
            Text(text)
                .font(.system(size: 27, weight: .black))
                .tracking(-0.8)
        }

        // Card Title: 13px, weight 700, uppercase, tracking 0.6px
        static func cardTitle(_ text: String) -> Text {
            Text(text.uppercased())
                .font(.system(size: 13, weight: .bold))
                .tracking(0.6)
        }

        // Metric Value: 28px, weight 900, tracking -1px
        static func metricValue(_ text: String) -> Text {
            Text(text)
                .font(.system(size: 28, weight: .black))
                .tracking(-1)
        }

        // Metric Label: 10px, weight 600, uppercase, tracking 0.5px
        static func metricLabel(_ text: String) -> Text {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
        }

        // Body: 13.5px, weight 400
        static func body(_ text: String) -> Text {
            Text(text)
                .font(.system(size: 13.5, weight: .regular))
        }

        // Body with line spacing (returns View)
        static func bodyParagraph(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 13.5, weight: .regular))
                .lineSpacing(13.5 * 0.6) // 1.6 line height
        }

        // Caption: 11px, weight 500
        static func caption(_ text: String) -> Text {
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }

        // Badge: 10px, weight 700, uppercase, tracking 0.5px
        static func badge(_ text: String) -> Text {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
        }

        // Section Header: 15px, weight 700, tracking -0.2px
        static func sectionHeader(_ text: String) -> Text {
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.2)
        }

        // Nav Label: 10px, weight 600, uppercase, tracking 0.3px
        static func navLabel(_ text: String) -> Text {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.3)
        }
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxxs: CGFloat = 4
        static let xxs: CGFloat = 6
        static let xs: CGFloat = 8      // Small gap
        static let sm: CGFloat = 10     // Grid gap
        static let md: CGFloat = 12     // Card margin, list item padding
        static let lg: CGFloat = 16     // Card padding
        static let xl: CGFloat = 18     // Page padding
        static let xxl: CGFloat = 20    // Hero card padding
        static let xxxl: CGFloat = 24   // Section spacing
    }

    // MARK: - Radius

    enum Radius {
        static let xs: CGFloat = 8      // Badge, chip
        static let sm: CGFloat = 10     // Tab pill
        static let md: CGFloat = 12     // Input, button
        static let lg: CGFloat = 14     // Button large
        static let xl: CGFloat = 16     // FAB
        static let xxl: CGFloat = 18    // Metric tile
        static let card: CGFloat = 20   // Card
        static let sheet: CGFloat = 30  // Bottom sheet
    }

    // MARK: - Shadows

    enum Shadow {
        static let card = (color: Color.black.opacity(0.08), radius: 5.0, x: 0.0, y: 3.0)
        static let cardElevated = (color: Color.black.opacity(0.12), radius: 10.0, x: 0.0, y: 4.0)
        static let fab = (color: Color(hex: "FF005E").opacity(0.3), radius: 8.0, x: 0.0, y: 8.0)
        static let button = (color: Color(hex: "FF005E").opacity(0.2), radius: 6.0, x: 0.0, y: 4.0)
    }

    // MARK: - Animation

    enum Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeOut(duration: 0.2)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let spring = SwiftUI.Animation.spring(duration: 0.5)
        static let springBouncy = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.7)
    }

    // MARK: - Haptics

    enum Haptics {
        static func light() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        static func medium() {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        static func heavy() {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }

        static func success() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        static func error() {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        static func warning() {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        static func selection() {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - Convenience Color Extensions

extension Color {
    // Quick access to theme colors
    static let themeAccent = NexusTheme.Colors.accent
    static let themeBackground = NexusTheme.Colors.background
    static let themeCard = NexusTheme.Colors.card
    static let themeCardAlt = NexusTheme.Colors.cardAlt
    static let themeTextPrimary = NexusTheme.Colors.textPrimary
    static let themeTextSecondary = NexusTheme.Colors.textSecondary
    static let themeTextTertiary = NexusTheme.Colors.textTertiary
    static let themeDivider = NexusTheme.Colors.divider

    // Semantic colors
    static let themeGreen = NexusTheme.Colors.Semantic.green
    static let themeBlue = NexusTheme.Colors.Semantic.blue
    static let themeAmber = NexusTheme.Colors.Semantic.amber
    static let themePurple = NexusTheme.Colors.Semantic.purple
    static let themeRed = NexusTheme.Colors.Semantic.red
}

// MARK: - View Modifiers

extension View {
    /// Apply theme card styling
    func themeCard(elevated: Bool = false) -> some View {
        self
            .padding(NexusTheme.Spacing.lg)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .shadow(
                color: elevated ? NexusTheme.Shadow.cardElevated.color : NexusTheme.Shadow.card.color,
                radius: elevated ? NexusTheme.Shadow.cardElevated.radius : NexusTheme.Shadow.card.radius,
                x: 0,
                y: elevated ? NexusTheme.Shadow.cardElevated.y : NexusTheme.Shadow.card.y
            )
    }

    /// Apply metric tile styling
    func themeMetricTile() -> some View {
        self
            .padding(NexusTheme.Spacing.lg)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.xxl)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.xxl)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
    }

    /// Apply glass card effect (for sidebar/overlays)
    func themeGlassCard() -> some View {
        self
            .padding(NexusTheme.Spacing.lg)
            .background(.ultraThinMaterial)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
    }

    /// Apply alert banner styling
    func themeAlertBanner() -> some View {
        self
            .padding(NexusTheme.Spacing.md)
            .background(NexusTheme.Colors.accent.opacity(0.10))
            .cornerRadius(NexusTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.md)
                    .stroke(NexusTheme.Colors.accent.opacity(0.20), lineWidth: 1)
            )
    }
}

// MARK: - Preview

#Preview("Theme Colors") {
    ScrollView {
        VStack(spacing: 20) {
            // Backgrounds
            Group {
                Text("Backgrounds")
                    .font(.headline)
                HStack(spacing: 10) {
                    colorSwatch("Background", NexusTheme.Colors.background)
                    colorSwatch("Card", NexusTheme.Colors.card)
                    colorSwatch("Card Alt", NexusTheme.Colors.cardAlt)
                }
            }

            // Accent
            Group {
                Text("Accent")
                    .font(.headline)
                colorSwatch("Accent", NexusTheme.Colors.accent)
            }

            // Semantic
            Group {
                Text("Semantic Colors")
                    .font(.headline)
                HStack(spacing: 10) {
                    colorSwatch("Green", NexusTheme.Colors.Semantic.green)
                    colorSwatch("Blue", NexusTheme.Colors.Semantic.blue)
                    colorSwatch("Amber", NexusTheme.Colors.Semantic.amber)
                    colorSwatch("Purple", NexusTheme.Colors.Semantic.purple)
                    colorSwatch("Red", NexusTheme.Colors.Semantic.red)
                }
            }

            // Text
            Group {
                Text("Text Colors")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Primary Text")
                        .foregroundColor(NexusTheme.Colors.textPrimary)
                    Text("Secondary Text")
                        .foregroundColor(NexusTheme.Colors.textSecondary)
                    Text("Tertiary Text")
                        .foregroundColor(NexusTheme.Colors.textTertiary)
                    Text("Muted Text")
                        .foregroundColor(NexusTheme.Colors.textMuted)
                }
                .padding()
                .background(NexusTheme.Colors.card)
                .cornerRadius(12)
            }

            // Typography
            Group {
                Text("Typography")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 12) {
                    NexusTheme.Typography.pageTitle("Page Title")
                    NexusTheme.Typography.cardTitle("Card Title")
                    NexusTheme.Typography.metricValue("8,240")
                    NexusTheme.Typography.metricLabel("Steps Today")
                    NexusTheme.Typography.body("Body text with proper line height and spacing for readability.")
                    NexusTheme.Typography.caption("Caption text")
                    NexusTheme.Typography.badge("Badge")
                }
                .padding()
                .background(NexusTheme.Colors.card)
                .cornerRadius(12)
            }
        }
        .padding()
    }
    .background(NexusTheme.Colors.background)
}

@ViewBuilder
private func colorSwatch(_ name: String, _ color: Color) -> some View {
    VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 60, height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        Text(name)
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}
