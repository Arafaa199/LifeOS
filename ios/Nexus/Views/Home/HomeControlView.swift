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

    // MARK: - Status Section

    private func statusSection(_ status: HomeStatus) -> some View {
        VStack(spacing: 16) {
            // Device Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Lights
                DeviceCard(
                    icon: "lightbulb.fill",
                    title: "Lights",
                    subtitle: status.lightsOn ? "On" : "Off",
                    isActive: status.lightsOn
                )

                // Monitors
                DeviceCard(
                    icon: "display",
                    title: "Monitors",
                    subtitle: status.monitorsOn ? "On" : "Off",
                    isActive: status.monitorsOn
                )

                // Vacuum
                if let vacuum = status.vacuum {
                    DeviceCard(
                        icon: "fan.fill",
                        title: "Vacuum",
                        subtitle: vacuum.stateDisplay,
                        isActive: vacuum.isCleaning,
                        badge: vacuum.battery.map { "\($0)%" }
                    )
                }

                // Camera
                if let camera = status.camera {
                    DeviceCard(
                        icon: "video.fill",
                        title: "Camera",
                        subtitle: camera.stateDisplay,
                        isActive: camera.isActive
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

// MARK: - Device Card

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

// MARK: - Preview

#Preview {
    HomeControlView()
}
