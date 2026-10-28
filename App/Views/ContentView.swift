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
    @ObservedObject private var router = MainWindowRouter.shared
    @State private var selectedDevice: WebOSDevice?
    @State private var showingAddDevice = false
    @State private var showingScanner = false
    /// The TV the user asked to remove, while the confirmation is up.
    @State private var deviceToRemove: WebOSDevice?

    /// Name of the selected TV, read from the manager so a rename shows up at once.
    private var windowTitle: String {
        guard let id = selectedDevice?.id,
              let device = deviceManager.devices.first(where: { $0.id == id }) else {
            return "TVs"
        }
        return device.name
    }

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
        .navigationTitle(windowTitle)
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
        .confirmationDialog(
            "Remove “\(deviceToRemove?.name ?? "TV")”?",
            isPresented: Binding(
                get: { deviceToRemove != nil },
                set: { if !$0 { deviceToRemove = nil } }
            ),
            titleVisibility: .visible,
            presenting: deviceToRemove
        ) { device in
            // Not the default button: Return must not remove a TV.
            Button("Remove TV", role: .destructive) {
                remove(device)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The TV will no longer be managed and its pairing key is deleted. You can add it again at any time.")
        }
        .onChange(of: selectedDevice) { _, device in
            router.selectedDeviceID = device?.id
        }
        .onChange(of: router.pendingSheet, initial: true) { _, sheet in
            // A menu command asked for a sheet; the window may have been
            // created just for it.
            guard let sheet else { return }
            router.pendingSheet = nil
            switch sheet {
            case .scan: showingScanner = true
            case .add: showingAddDevice = true
            }
        }
        .background(WindowAccessor { MainWindowGate.shared.windowAttached($0) })
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
                            Button("Remove TV…", role: .destructive) {
                                deviceToRemove = device
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
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
        // Looked up by id on every access: the TV can be removed while the
        // detail view is still being rendered. Then reads fall back to the
        // last known value and writes are ignored.
        Binding(
            get: { deviceManager.devices.first { $0.id == device.id } ?? device },
            set: { updated in
                guard let index = deviceManager.devices.firstIndex(where: { $0.id == device.id }) else { return }
                deviceManager.devices[index] = updated
            }
        )
    }

    private func remove(_ device: WebOSDevice) {
        if selectedDevice?.id == device.id { selectedDevice = nil }
        deviceManager.removeDevice(device)
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
