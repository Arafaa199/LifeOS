import SwiftUI

struct HomeStatusCard: View {
    @ObservedObject var viewModel: HomeViewModel
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "house.fill")
                        .foregroundColor(.orange)
                    Text("Home")
                        .font(.headline)
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = viewModel.errorMessage {
                    // Error state
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let status = viewModel.homeStatus {
                    // Device grid
                    HStack(spacing: 16) {
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
                    HStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 32, height: 32)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 40, height: 10)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isOn ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isOn ? .green : .gray)
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)

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
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isOn ? .green : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func batteryIcon(for level: Int) -> String {
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        return "battery.25"
    }

    private func batteryColor(for level: Int) -> Color {
        if level > 50 { return .green }
        if level > 20 { return .orange }
        return .red
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Uses shared instance - status shown will be current runtime state
        HomeStatusCard(viewModel: HomeViewModel.shared)
    }
    .padding()
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
