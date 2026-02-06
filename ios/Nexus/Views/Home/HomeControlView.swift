import SwiftUI

struct HomeControlView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    if let status = viewModel.homeStatus {
                        // Lights Section
                        if let light = status.lights?["hue_lightstrip"] {
                            deviceSection("Lights") {
                                LightControlRow(
                                    light: light,
                                    onToggle: { await viewModel.toggleDevice(light.entityId) },
                                    onBrightnessChange: { await viewModel.setLightBrightness(light.entityId, brightness: $0) }
                                )
                            }
                        }

                        // Office Section
                        deviceSection("Office") {
                            if let leftMon = status.switches?["left_monitor"] {
                                SwitchRow(
                                    icon: "display",
                                    name: "Left Monitor",
                                    state: leftMon,
                                    onToggle: { await viewModel.toggleDevice(leftMon.entityId) }
                                )
                            }
                            if let rightMon = status.switches?["right_monitor"] {
                                SwitchRow(
                                    icon: "display",
                                    name: "Right Monitor",
                                    state: rightMon,
                                    onToggle: { await viewModel.toggleDevice(rightMon.entityId) }
                                )
                            }
                            if let printer = status.switches?["printer"] {
                                SwitchRow(
                                    icon: "printer.fill",
                                    name: "3D Printer",
                                    state: printer,
                                    onToggle: { await viewModel.toggleDevice(printer.entityId) }
                                )
                            }
                        }

                        // Vacuum Section
                        if let vacuum = status.vacuum {
                            deviceSection("Cleaning") {
                                VacuumControlCard(
                                    vacuum: vacuum,
                                    onStart: { await viewModel.vacuumCommand(.start) },
                                    onReturn: { await viewModel.vacuumCommand(.returnToBase) },
                                    onLocate: { await viewModel.vacuumCommand(.locate) }
                                )
                            }
                        }

                        // Camera Section
                        if let camera = status.camera {
                            deviceSection("Security") {
                                CameraControlRow(
                                    camera: camera,
                                    onToggleSleep: {
                                        // Toggle camera sleep switch
                                        await viewModel.toggleDevice("switch.ezviz_camera_sleep")
                                    }
                                )
                            }
                        }
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
            .navigationTitle("Home Control")
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
                }
            }
            .refreshable {
                await viewModel.fetchStatus()
            }
        }
    }

    // MARK: - Components

    private func deviceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 1) {
                content()
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button("Dismiss") {
                viewModel.errorMessage = nil
            }
            .font(.subheadline.weight(.medium))
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Light Control Row

struct LightControlRow: View {
    let light: LightState
    let onToggle: () async -> Void
    let onBrightnessChange: (Int) async -> Void

    @State private var brightness: Double = 80
    @State private var isChanging = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title2)
                    .foregroundColor(light.isOn ? .yellow : .gray)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hue Lightstrip")
                        .font(.body)
                    if light.isOn, let pct = light.brightnessPct {
                        Text("\(pct)% brightness")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { light.isOn },
                    set: { _ in
                        Task { await onToggle() }
                    }
                ))
                .labelsHidden()
            }

            if light.isOn {
                HStack {
                    Image(systemName: "sun.min")
                        .foregroundColor(.secondary)
                    Slider(value: $brightness, in: 1...100, step: 1) { editing in
                        if !editing && !isChanging {
                            isChanging = true
                            Task {
                                await onBrightnessChange(Int(brightness))
                                isChanging = false
                            }
                        }
                    }
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.yellow)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .onAppear {
            brightness = Double(light.brightnessPct ?? 80)
        }
    }
}

// MARK: - Switch Row

struct SwitchRow: View {
    let icon: String
    let name: String
    let state: SwitchState
    let onToggle: () async -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(state.isOn ? .green : .gray)
                .frame(width: 32)

            Text(name)
                .font(.body)

            Spacer()

            Toggle("", isOn: Binding(
                get: { state.isOn },
                set: { _ in
                    Task { await onToggle() }
                }
            ))
            .labelsHidden()
        }
        .padding()
    }
}

// MARK: - Vacuum Control Card

struct VacuumControlCard: View {
    let vacuum: VacuumState
    let onStart: () async -> Void
    let onReturn: () async -> Void
    let onLocate: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "fan.fill")
                    .font(.title2)
                    .foregroundColor(vacuum.isCleaning ? .green : .gray)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Eufy X10 Pro")
                        .font(.body)
                    Text(vacuum.stateDisplay)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let battery = vacuum.battery {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon(for: battery))
                            .foregroundColor(batteryColor(for: battery))
                        Text("\(battery)%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task { await onStart() }
                } label: {
                    Label("Clean", systemImage: "play.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(vacuum.isCleaning ? Color.gray.opacity(0.2) : Color.green.opacity(0.2))
                        .foregroundColor(vacuum.isCleaning ? .gray : .green)
                        .cornerRadius(8)
                }
                .disabled(vacuum.isCleaning)

                Button {
                    Task { await onReturn() }
                } label: {
                    Label("Dock", systemImage: "house.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(vacuum.isDocked ? Color.gray.opacity(0.2) : Color.blue.opacity(0.2))
                        .foregroundColor(vacuum.isDocked ? .gray : .blue)
                        .cornerRadius(8)
                }
                .disabled(vacuum.isDocked)

                Button {
                    Task { await onLocate() }
                } label: {
                    Image(systemName: "location.fill")
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
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

// MARK: - Camera Control Row

struct CameraControlRow: View {
    let camera: CameraState
    let onToggleSleep: () async -> Void

    var body: some View {
        HStack {
            Image(systemName: "video.fill")
                .font(.title3)
                .foregroundColor(camera.isActive ? .green : .gray)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("EZVIZ Camera")
                    .font(.body)
                Text(camera.stateDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Sleep Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("", isOn: Binding(
                    get: { camera.sleeping },
                    set: { _ in
                        Task { await onToggleSleep() }
                    }
                ))
                .labelsHidden()
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    HomeControlView(viewModel: {
        let vm = HomeViewModel()
        vm.homeStatus = HomeStatus(
            lights: ["hue_lightstrip": LightState(entityId: "light.hue", state: "on", brightness: 200, brightnessPct: 80)],
            switches: [
                "left_monitor": SwitchState(entityId: "switch.left", state: "off"),
                "right_monitor": SwitchState(entityId: "switch.right", state: "on"),
                "printer": SwitchState(entityId: "switch.printer", state: "off")
            ],
            vacuum: VacuumState(entityId: "vacuum.eufy", state: "docked", battery: 87, fanSpeed: "standard"),
            camera: CameraState(entityId: "camera.ezviz", state: "idle", sleeping: false),
            presence: nil
        )
        return vm
    }())
}
