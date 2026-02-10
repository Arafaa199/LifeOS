import SwiftUI

/// Simple launcher view for Home Assistant.
/// All device control is handled by the native HA Companion app or web dashboard.
struct HomeControlView: View {
    @ObservedObject var viewModel = HomeViewModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    if let status = viewModel.homeStatus {
                        // Status Overview
                        statusSection(status)

                        // Open HA Button
                        openHAButton
                    } else if viewModel.isLoading {
                        ProgressView("Loading devices...")
                            .padding(.top, 40)
                    } else {
                        ContentUnavailableView(
                            "No Devices",
                            systemImage: "house",
                            description: Text("Unable to load home devices")
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.fetchStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel("Refresh home status")
                }
            }
            .refreshable {
                await viewModel.fetchStatus()
            }
            .task {
                if viewModel.homeStatus == nil {
                    await viewModel.fetchStatus()
                }
            }
        }
    }

    // MARK: - Device Control Actions

    private func toggleLights(_ status: HomeStatus) async {
        await viewModel.controlDevice(
            entityId: "light.hue_lightstrip_plus_1",
            action: status.lightsOn ? .turnOff : .turnOn
        )
    }

    private func controlMonitor(action: HomeAction, entityId: String) async {
        await viewModel.controlDevice(entityId: entityId, action: action)
    }

    private func controlVacuum(action: HomeAction, vacuum: VacuumState) async {
        await viewModel.controlDevice(
            entityId: vacuum.entityId,
            action: action
        )
    }

    // MARK: - Status Section

    private func statusSection(_ status: HomeStatus) -> some View {
        VStack(spacing: 16) {
            // Device Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Lights
                LightsDeviceCard(
                    isActive: status.lightsOn,
                    isControlling: viewModel.controllingDevice?.contains("light") ?? false
                ) {
                    await toggleLights(status)
                }

                // Monitors
                MonitorsDeviceCard(
                    isActive: status.monitorsOn,
                    switches: status.switches,
                    isControlling: viewModel.controllingDevice?.contains("monitor") ?? false
                ) { action, entityId in
                    await controlMonitor(action: action, entityId: entityId)
                }

                // Vacuum
                if let vacuum = status.vacuum {
                    VacuumDeviceCard(
                        vacuum: vacuum,
                        isControlling: viewModel.controllingDevice?.contains("vacuum") ?? false
                    ) { action in
                        await controlVacuum(action: action, vacuum: vacuum)
                    }
                }

                // Camera
                if let camera = status.camera {
                    CameraDeviceCard(
                        camera: camera
                    )
                }
            }

            // Last Updated
            if let lastUpdated = viewModel.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Open HA Button

    private var openHAButton: some View {
        Button {
            viewModel.openHomeAssistant()
        } label: {
            HStack {
                Image(systemName: "house.fill")
                Text("Open Home Assistant")
                Spacer()
                Image(systemName: "arrow.up.right.square")
            }
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Device Cards

// Base DeviceCard for read-only devices
private struct DeviceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isActive: Bool
    var badge: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundColor(isActive ? .green : .gray)
                    )

                if let badge = badge {
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .offset(x: 8, y: -4)
                }
            }

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(isActive ? .green : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// Lights control card
private struct LightsDeviceCard: View {
    let isActive: Bool
    let isControlling: Bool
    let onToggle: () async -> Void

    var body: some View {
        Button(action: {
            Task { await onToggle() }
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "lightbulb.fill")
                                .font(.title2)
                                .foregroundColor(isActive ? .green : .gray)
                        )

                    if isControlling {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                Text("Lights")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(isActive ? "On" : "Off")
                    .font(.caption)
                    .foregroundColor(isActive ? .green : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .disabled(isControlling)
    }
}

// Monitors control card
private struct MonitorsDeviceCard: View {
    let isActive: Bool
    let switches: [String: SwitchState]?
    let isControlling: Bool
    let onControl: (HomeAction, String) async -> Void

    private var leftMonitorOn: Bool {
        switches?["left_monitor"]?.isOn ?? false
    }

    private var rightMonitorOn: Bool {
        switches?["right_monitor"]?.isOn ?? false
    }

    var body: some View {
        VStack(spacing: 8) {
            Menu {
                Button {
                    Task {
                        await onControl(.toggle, "switch.left_monitor")
                    }
                } label: {
                    HStack {
                        Text(leftMonitorOn ? "Turn Off" : "Turn On")
                        Text("Left Monitor")
                    }
                }

                Button {
                    Task {
                        await onControl(.toggle, "switch.right_monitor")
                    }
                } label: {
                    HStack {
                        Text(rightMonitorOn ? "Turn Off" : "Turn On")
                        Text("Right Monitor")
                    }
                }
            } label: {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "display")
                                    .font(.title2)
                                    .foregroundColor(isActive ? .green : .gray)
                            )

                        if isControlling {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }

                    Text("Monitors")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(isActive ? "On" : "Off")
                        .font(.caption)
                        .foregroundColor(isActive ? .green : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .disabled(isControlling)
        }
    }
}

// Vacuum control card
private struct VacuumDeviceCard: View {
    let vacuum: VacuumState
    let isControlling: Bool
    let onControl: (HomeAction) async -> Void

    var body: some View {
        VStack(spacing: 8) {
            Menu {
                if !vacuum.isCleaning {
                    Button {
                        Task {
                            await onControl(.start)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Cleaning")
                        }
                    }
                } else {
                    Button {
                        Task {
                            await onControl(.stop)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                    }
                }

                Button {
                    Task {
                        await onControl(.returnToBase)
                    }
                } label: {
                    HStack {
                        Image(systemName: "house.fill")
                        Text("Return to Base")
                    }
                }
            } label: {
                VStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        Circle()
                            .fill(vacuum.isCleaning ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "fan.fill")
                                    .font(.title2)
                                    .foregroundColor(vacuum.isCleaning ? .green : .gray)
                            )

                        if let battery = vacuum.battery {
                            Text("\(battery)%")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                                .offset(x: 8, y: -4)
                        }

                        if isControlling {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }

                    Text("Vacuum")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(vacuum.stateDisplay)
                        .font(.caption)
                        .foregroundColor(vacuum.isCleaning ? .green : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .disabled(isControlling)
        }
    }
}

// Camera card (read-only)
private struct CameraDeviceCard: View {
    let camera: CameraState

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(camera.isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "video.fill")
                            .font(.title2)
                            .foregroundColor(camera.isActive ? .green : .gray)
                    )
            }

            Text("Camera")
                .font(.subheadline)
                .fontWeight(.medium)

            Text(camera.stateDisplay)
                .font(.caption)
                .foregroundColor(camera.isActive ? .green : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    HomeControlView()
}
