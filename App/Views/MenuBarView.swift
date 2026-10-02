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
    @ObservedObject private var speakers = DeviceManager.shared.speakers

    var body: some View {
        VStack(alignment: .leading, spacing: MenuMetrics.cardSpacing) {
            if deviceManager.devices.isEmpty {
                MenuCard {
                    MenuCardHeader(title: "No TV yet", status: "Add your LG TV to control it") {
                        SymbolTile(systemName: "tv", tint: .gray)
                    }
                    CapsuleButton(title: "Add a TV…") { openMainWindow() }
                }
            } else {
                ForEach(deviceManager.devices.filter(\.enabled)) { device in
                    DeviceMenuSection(device: device)
                }
            }

            if speakers.isEnabled {
                SpeakerMenuSection(speakers: speakers)
            }

            MenuCard {
                MenuCaption(text: "Displays")
                DisplayScalingSection()
            }

            footer
        }
        .padding(MenuMetrics.panelPadding)
        .frame(width: MenuMetrics.panelWidth)
        .task {
            deviceManager.startPowerEventMonitoring()
            deviceManager.ensureMediaKeyTap()
            await deviceManager.refreshAllStatuses()
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                openMainWindow()
            } label: {
                Label("Open LGTV Companion", systemImage: "macwindow")
                    .font(.system(size: 12))
            }

            Spacer()

            Button {
                Task { await deviceManager.refreshAllStatuses() }
                speakers.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
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
    @State private var busy = false
    @ObservedObject private var speakers = DeviceManager.shared.speakers

    private static let tvVolumeRange: ClosedRange<Double> = 0...100
    private static let hdmiInputs = 1...4

    private var status: DeviceStatus? { deviceManager.deviceStatuses[device.id] }

    /// With speaker control on, the speakers' own card is the volume
    /// control. The software row would only repeat "100 %", so it is hidden
    /// unless the software volume is actually attenuating (the fallback when
    /// the speakers are unreachable).
    private var hidesVolumeRow: Bool {
        speakers.isEnabled && usesSoftwareVolume
            && deviceManager.softwareVolumeLevel >= 1 && !deviceManager.softwareVolumeMuted
    }

    /// True when this card's volume controls drive the Mac-side software
    /// volume instead of the TV. Only the primary TV (the one the volume
    /// keys go to) can be in that mode.
    private var usesSoftwareVolume: Bool {
        deviceManager.softwareVolumeActive
            && deviceManager.devices.first(where: \.enabled)?.id == device.id
    }

    private var softwareVolumePercent: Binding<Double> {
        Binding(
            get: { (deviceManager.softwareVolumeLevel * 100).rounded() },
            set: { deviceManager.setSoftwareVolume(level: $0 / 100) }
        )
    }

    var body: some View {
        MenuCard {
            MenuCardHeader(title: device.name, status: statusText, statusColor: statusColor) {
                SymbolTile(systemName: "tv")
            }

            HStack(spacing: 4) {
                ControlTile(title: "Screen On", systemName: "tv", isDisabled: busy) {
                    run { try await deviceManager.screenOn(device) }
                }
                ControlTile(title: "Screen Off", systemName: "tv.slash", isDisabled: busy) {
                    run { try await deviceManager.screenOff(device) }
                }
                ControlTile(title: "Wake", systemName: "sunrise", isDisabled: busy) {
                    run {
                        try await deviceManager.powerOnDevice(device)
                        await deviceManager.refreshStatus(for: device)
                    }
                }
                ControlTile(title: "Power Off", systemName: "power", isDisabled: busy) {
                    run { try await deviceManager.fullPowerOff(device) }
                }
            }

            if hidesVolumeRow {
                EmptyView()
            } else if usesSoftwareVolume {
                softwareVolumeRow
            } else {
                tvVolumeRow
            }

            VStack(alignment: .leading, spacing: 6) {
                MenuCaption(text: "Input")
                HStack(spacing: 6) {
                    ForEach(Self.hdmiInputs, id: \.self) { number in
                        CapsuleButton(title: "HDMI \(number)") {
                            run { try await deviceManager.switchInput("HDMI_\(number)", for: device) }
                        }
                    }
                }
            }
        }
        .onChange(of: status?.volume) { _, newValue in
            if let newValue = newValue { volume = Double(newValue) }
        }
        .onAppear {
            if let current = status?.volume { volume = Double(current) }
        }
    }

    /// Volume on the TV itself (TV speakers, ARC).
    private var tvVolumeRow: some View {
        VolumeRow(
            value: $volume,
            range: Self.tvVolumeRange,
            isMuted: status?.muted ?? false,
            isEnabled: status?.isReachable ?? false,
            accessibilityLabel: "TV volume",
            onToggleMute: {
                run {
                    try await deviceManager.setMute(!(status?.muted ?? false), for: device)
                    await deviceManager.refreshStatus(for: device)
                }
            },
            onCommit: {
                run { try await deviceManager.setVolume(Int(volume), for: device) }
            }
        )
    }

    /// Volume of the Mac's sound, for TV outputs with a fixed level (optical).
    /// Local, so it follows the slider live and works while the TV is busy.
    private var softwareVolumeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            VolumeRow(
                value: softwareVolumePercent,
                range: Self.tvVolumeRange,
                isMuted: deviceManager.softwareVolumeMuted,
                accessibilityLabel: "Mac volume",
                onToggleMute: { deviceManager.toggleSoftwareMute() }
            )
            Text("Mac volume. The TV's sound output has a fixed level.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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

    private func run(_ action: @escaping () async throws -> Void) {
        busy = true
        Task {
            try? await action()
            await MainActor.run { busy = false }
        }
    }
}

// MARK: - Speakers (Edifier, Bluetooth)

struct SpeakerMenuSection: View {
    @ObservedObject var speakers: EdifierSpeakerController
    @State private var sliderVolume: Double = 0

    var body: some View {
        MenuCard {
            MenuCardHeader(title: speakers.deviceName ?? "Speakers", status: statusText,
                           statusColor: statusColor) {
                SpeakerArtwork()
            }

            VolumeRow(
                value: $sliderVolume,
                range: 0...Double(speakers.maxVolume),
                isMuted: speakers.isMuted,
                isEnabled: speakers.volume != nil,
                accessibilityLabel: "Speaker volume",
                onToggleMute: { speakers.toggleMute() },
                onCommit: { speakers.setVolume(Int(sliderVolume)) }
            )

            VStack(alignment: .leading, spacing: 6) {
                MenuCaption(text: "Subwoofer")
                CapsulePicker(
                    options: EdifierSubOutLevel.allCases,
                    selection: speakers.subOut,
                    label: { $0.label },
                    isEnabled: speakers.subOut != nil,
                    onSelect: { speakers.setSubOut($0) }
                )
            }

            if speakers.state == .unavailable {
                HStack {
                    Text("Close the Edifier app on your phone, then retry.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { speakers.refresh() }
                        .controlSize(.small)
                }
            }
        }
        .onAppear {
            speakers.refresh()
            if let volume = speakers.volume { sliderVolume = Double(volume) }
        }
        .onChange(of: speakers.volume) { _, newValue in
            if let newValue = newValue { sliderVolume = Double(newValue) }
        }
    }

    private var statusText: String {
        switch speakers.state {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .unavailable: return "Not reachable"
        case .idle: return speakers.volume == nil ? "Not connected" : "Standby"
        }
    }

    private var statusColor: Color {
        switch speakers.state {
        case .connected: return .green
        case .connecting: return .orange
        case .unavailable, .idle: return .gray
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
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displays) { display in
                    HStack {
                        Image(systemName: "display")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(display.name)
                            .font(.system(size: 12))
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
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
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
