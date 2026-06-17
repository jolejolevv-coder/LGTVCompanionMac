//
//  ContentView.swift
//  LGTV Companion
//
//  Main application view
//

import LGTVCompanionShared
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var selectedDevice: WebOSDevice?
    @State private var showingAddDevice = false
    @State private var showingScanner = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            deviceListSidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 260)
        } detail: {
            if let device = selectedDevice,
               deviceManager.devices.contains(where: { $0.id == device.id }) {
                DeviceDetailView(device: binding(for: device))
                    .id(device.id)
            } else {
                emptyStateView
            }
        }
        .navigationTitle("LGTV Companion")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingScanner = true
                } label: {
                    Label("Scan for TVs", systemImage: "magnifyingglass")
                }
                .help("Scan the network for LG TVs")

                Button {
                    showingAddDevice = true
                } label: {
                    Label("Add TV", systemImage: "plus")
                }
                .help("Add a TV manually")

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showingAddDevice) {
            AddDeviceView()
                .environmentObject(deviceManager)
        }
        .sheet(isPresented: $showingScanner) {
            DeviceScannerView()
                .environmentObject(deviceManager)
        }
        .sheet(isPresented: $showingSettings) {
            VStack(spacing: 0) {
                SettingsView()
                    .environmentObject(deviceManager)
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { showingSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
        }
        .task {
            deviceManager.ensureMediaKeyTap()
            await deviceManager.refreshAllStatuses()
        }
    }

    private var deviceListSidebar: some View {
        List(selection: $selectedDevice) {
            Section("My TVs") {
                ForEach(deviceManager.devices) { device in
                    DeviceListItem(device: device)
                        .tag(device)
                        .contextMenu {
                            Button("Refresh Status") {
                                Task { await deviceManager.refreshStatus(for: device) }
                            }
                            Divider()
                            Button("Remove…", role: .destructive) {
                                confirmRemove(device)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text("Made by Nahobino")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .overlay {
            if deviceManager.devices.isEmpty {
                ContentUnavailableView {
                    Label("No TVs", systemImage: "tv")
                } description: {
                    Text("Scan your network or add a TV manually.")
                } actions: {
                    Button("Scan Network") { showingScanner = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("Select a TV", systemImage: "tv.and.mediabox")
        } description: {
            Text("Choose a TV from the sidebar to view its status and settings.")
        }
    }

    private func binding(for device: WebOSDevice) -> Binding<WebOSDevice> {
        guard let index = deviceManager.devices.firstIndex(where: { $0.id == device.id }) else {
            fatalError("Device not found")
        }
        return $deviceManager.devices[index]
    }

    private func confirmRemove(_ device: WebOSDevice) {
        let alert = NSAlert()
        alert.messageText = "Remove “\(device.name)”?"
        alert.informativeText = "The TV will no longer be managed. You can add it again at any time."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if selectedDevice?.id == device.id { selectedDevice = nil }
            deviceManager.removeDevice(device)
        }
    }
}

// MARK: - Device List Item

struct DeviceListItem: View {
    @EnvironmentObject var deviceManager: DeviceManager
    let device: WebOSDevice

    private var status: DeviceStatus? { deviceManager.deviceStatuses[device.id] }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tv")
                .font(.title3)
                .foregroundStyle(device.enabled ? Color.accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if device.autoManage && device.enabled {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .help("Follows Mac sleep/wake")
            }
            if !device.enabled {
                Image(systemName: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Disabled")
            }
        }
        .padding(.vertical, 3)
    }

    private var statusColor: Color {
        guard let status = status else { return .gray }
        if status.isScreenOn { return .green }
        if status.isReachable { return .orange }
        return .gray
    }

    private var statusText: String {
        guard device.enabled else { return "Disabled" }
        guard let status = status else { return device.ipAddress }
        return status.powerState ?? "Offline"
    }
}
