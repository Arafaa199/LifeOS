import SwiftUI

struct HomeStatusCard: View {
    @ObservedObject var viewModel: HomeViewModel
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            // accessibility set on outer button below
            VStack(alignment: .leading, spacing: NexusTheme.Spacing.md) {
                // Header
                HStack {
                    Image(systemName: "house.fill")
                        .foregroundColor(NexusTheme.Colors.Semantic.amber)
                    Text("Home")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(NexusTheme.Colors.textPrimary)
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textMuted)
                            .accessibilityHidden(true)
                    }
                }

                if let error = viewModel.errorMessage {
                    // Error state
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    }
                } else if let status = viewModel.homeStatus {
                    // Device grid
                    HStack(spacing: NexusTheme.Spacing.lg) {
                        // Lights
                        DeviceIndicator(
                            icon: "lightbulb.fill",
                            label: "Lights",
                            state: status.lightsOn ? "On" : "Off",
                            isOn: status.lightsOn
                        )

                        // Monitors
                        DeviceIndicator(
                            icon: "display",
                            label: "Monitors",
                            state: status.monitorsOn ? "On" : "Off",
                            isOn: status.monitorsOn
                        )

                        // Vacuum
                        if let vacuum = status.vacuum {
                            DeviceIndicator(
                                icon: "fan.fill",
                                label: "Vacuum",
                                state: vacuum.stateDisplay,
                                isOn: vacuum.isCleaning,
                                battery: vacuum.battery
                            )
                        }

                        // Camera
                        if let camera = status.camera {
                            DeviceIndicator(
                                icon: "video.fill",
                                label: "Camera",
                                state: camera.stateDisplay,
                                isOn: camera.isActive
                            )
                        }
                    }
                } else {
                    // Loading placeholder
                    HStack(spacing: NexusTheme.Spacing.lg) {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(spacing: NexusTheme.Spacing.xxxs) {
                                Circle()
                                    .fill(NexusTheme.Colors.cardAlt)
                                    .frame(width: 32, height: 32)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(NexusTheme.Colors.cardAlt)
                                    .frame(width: 40, height: 10)
                            }
                        }
                    }
                }
            }
            .padding(NexusTheme.Spacing.lg)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Home status, tap to open Home Assistant")
    }
}

// MARK: - Device Indicator

struct DeviceIndicator: View {
    let icon: String
    let label: String
    let state: String
    let isOn: Bool
    var battery: Int? = nil

    var body: some View {
        VStack(spacing: NexusTheme.Spacing.xxxs) {
            ZStack {
                Circle()
                    .fill(isOn ? NexusTheme.Colors.Semantic.green.opacity(0.15) : NexusTheme.Colors.cardAlt)
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isOn ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.textTertiary)
            }

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(NexusTheme.Colors.textSecondary)

            if let battery = battery {
                HStack(spacing: 2) {
                    Image(systemName: batteryIcon(for: battery))
                        .font(.system(size: 8))
                    Text("\(battery)%")
                        .font(.system(size: 9))
                }
                .foregroundColor(batteryColor(for: battery))
            } else {
                Text(state)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isOn ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(state)")
    }

    private func batteryIcon(for level: Int) -> String {
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        return "battery.25"
    }

    private func batteryColor(for level: Int) -> Color {
        if level > 50 { return NexusTheme.Colors.Semantic.green }
        if level > 20 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.red
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Uses shared instance - status shown will be current runtime state
        HomeStatusCard(viewModel: HomeViewModel.shared)
    }
    .padding()
    .background(NexusTheme.Colors.background)
    .onAppear {
        // Set mock data for preview
        HomeViewModel.shared.homeStatus = HomeStatus(
            lights: ["hue": LightState(entityId: "light.hue", state: "on", brightness: 200, brightnessPct: 80)],
            switches: [
                "left_monitor": SwitchState(entityId: "switch.left", state: "off"),
                "right_monitor": SwitchState(entityId: "switch.right", state: "off")
            ],
            vacuum: VacuumState(entityId: "vacuum.eufy", state: "docked", battery: 87, fanSpeed: "standard"),
            camera: CameraState(entityId: "camera.ezviz", state: "idle", sleeping: false),
            presence: nil
        )
    }
}
