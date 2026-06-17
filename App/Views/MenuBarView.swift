//
//  MenuBarView.swift
//  LGTV Companion
//
//  Quick controls in the macOS menu bar
//

import LGTVCompanionShared
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if deviceManager.devices.isEmpty {
                Text("No TVs configured")
                    .foregroundStyle(.secondary)
                Button("Add a TV…") { openMainWindow() }
            } else {
                ForEach(deviceManager.devices.filter(\.enabled)) { device in
                    DeviceMenuSection(device: device)
                    Divider()
                }
            }

            Text("Display Resolution")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            DisplayScalingSection()
            Divider()

            HStack {
                Button {
                    openMainWindow()
                } label: {
                    Label("Open App", systemImage: "macwindow")
                }

                Spacer()

                Button {
                    Task { await deviceManager.refreshAllStatuses() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 300)
        .task {
            deviceManager.startPowerEventMonitoring()
            deviceManager.ensureMediaKeyTap()
            await deviceManager.refreshAllStatuses()
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Per-device controls

struct DeviceMenuSection: View {
    @EnvironmentObject var deviceManager: DeviceManager
    let device: WebOSDevice

    @State private var volume: Double = 0
    @State private var hasVolume = false
    @State private var busy = false

    private var status: DeviceStatus? { deviceManager.deviceStatuses[device.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: name + status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(device.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Power / screen controls
            HStack(spacing: 6) {
                controlButton("Screen On", icon: "tv") {
                    try await deviceManager.screenOn(device)
                }
                controlButton("Screen Off", icon: "tv.slash") {
                    try await deviceManager.screenOff(device)
                }
                controlButton("Wake", icon: "sunrise") {
                    try await deviceManager.powerOnDevice(device)
                    await deviceManager.refreshStatus(for: device)
                }
                controlButton("Power Off", icon: "power") {
                    try await deviceManager.fullPowerOff(device)
                }
            }

            // Volume
            HStack(spacing: 8) {
                Button {
                    run { try await deviceManager.setMute(!(status?.muted ?? false), for: device)
                          await deviceManager.refreshStatus(for: device) }
                } label: {
                    Image(systemName: (status?.muted ?? false) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)

                Slider(value: $volume, in: 0...100, step: 1) { editing in
                    if !editing {
                        run { try await deviceManager.setVolume(Int(volume), for: device) }
                    }
                }
                .disabled(!(status?.isReachable ?? false))

                Text("\(Int(volume))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 24, alignment: .trailing)
            }

            // Inputs
            HStack(spacing: 6) {
                Text("Input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(1...4, id: \.self) { n in
                    Button("HDMI \(n)") {
                        run { try await deviceManager.switchInput("HDMI_\(n)", for: device) }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .onChange(of: status?.volume) { _, newValue in
            if let v = newValue {
                volume = Double(v)
                hasVolume = true
            }
        }
        .onAppear {
            if let v = status?.volume { volume = Double(v); hasVolume = true }
        }
    }

    private var statusColor: Color {
        guard let status = status else { return .gray }
        if status.isScreenOn { return .green }
        if status.isReachable { return .orange }
        return .gray
    }

    private var statusText: String {
        guard let status = status else { return "Unknown" }
        return status.powerState ?? "Offline"
    }

    private func controlButton(_ title: String, icon: String,
                               _ action: @escaping () async throws -> Void) -> some View {
        Button {
            run(action)
        } label: {
            Image(systemName: icon)
                .frame(maxWidth: .infinity)
        }
        .help(title)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(busy)
    }

    private func run(_ action: @escaping () async throws -> Void) {
        busy = true
        Task {
            try? await action()
            await MainActor.run { busy = false }
        }
    }
}

// MARK: - Resolution / Scaling (Windows-style 100% / 150% / 200%)

struct DisplayScalingSection: View {
    @State private var displays: [DisplayInfo] = []
    @State private var currentModes: [CGDirectDisplayID: DisplayModeInfo] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if displays.isEmpty {
                Text("No external display")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displays) { display in
                    HStack {
                        Image(systemName: "rectangle.on.rectangle")
                            .foregroundStyle(.secondary)
                        Text(display.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()

                        Menu {
                            ForEach(DisplayControl.scalingModes(for: display.id)) { mode in
                                Button {
                                    DisplayControl.setMode(mode, on: display.id)
                                    refresh()
                                } label: {
                                    if currentModes[display.id] == mode {
                                        Label(mode.label, systemImage: "checkmark")
                                    } else {
                                        Text(mode.label)
                                    }
                                }
                            }
                        } label: {
                            Text(currentLabel(for: display))
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
        }
        .onAppear { refresh() }
    }

    private func currentLabel(for display: DisplayInfo) -> String {
        if let mode = currentModes[display.id] {
            return "\(mode.width) × \(mode.height) (\(mode.scalePercent)%)"
        }
        return "Resolution"
    }

    private func refresh() {
        displays = DisplayControl.activeDisplays()
        var modes: [CGDirectDisplayID: DisplayModeInfo] = [:]
        for display in displays {
            modes[display.id] = DisplayControl.currentMode(for: display.id)
        }
        currentModes = modes
    }
}
