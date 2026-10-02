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

            if speakers.isEnabled {
                SpeakerMenuSection(speakers: speakers)
                Divider()
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
    @ObservedObject private var speakers = DeviceManager.shared.speakers

    private var status: DeviceStatus? { deviceManager.deviceStatuses[device.id] }

    /// With speaker control on, the speakers' own row below is the volume
    /// control. The software row would only repeat "100 %", so it is hidden
    /// unless the software volume is actually attenuating (the fallback when
    /// the speakers are unreachable).
    private var hidesVolumeRow: Bool {
        speakers.isEnabled && usesSoftwareVolume
            && deviceManager.softwareVolumeLevel >= 1 && !deviceManager.softwareVolumeMuted
    }

    /// True when this row's volume controls drive the Mac-side software
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
            if hidesVolumeRow {
                EmptyView()
            } else if usesSoftwareVolume {
                softwareVolumeRow
            } else {
                tvVolumeRow
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

    /// Volume on the TV itself (TV speakers, ARC).
    private var tvVolumeRow: some View {
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
    }

    /// Volume of the Mac's sound, for TV outputs with a fixed level (optical).
    /// Local, so it follows the slider live and works while the TV is busy.
    private var softwareVolumeRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Button {
                    deviceManager.toggleSoftwareMute()
                } label: {
                    Image(systemName: deviceManager.softwareVolumeMuted
                          ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)

                Slider(value: softwareVolumePercent, in: 0...100)

                Text("\(Int(softwareVolumePercent.wrappedValue))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 24, alignment: .trailing)
            }
            Text("Mac volume. The TV's sound output has a fixed level.")
                .font(.caption2)
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

// MARK: - Speakers (Edifier, Bluetooth)

struct SpeakerMenuSection: View {
    @ObservedObject var speakers: EdifierSpeakerController
    @State private var sliderVolume: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hifispeaker.2.fill")
                    .foregroundStyle(.secondary)
                Text(speakers.deviceName ?? "Speakers")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: speakers.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)

                Slider(value: $sliderVolume, in: 0...Double(speakers.maxVolume), step: 1) { editing in
                    if !editing { speakers.setVolume(Int(sliderVolume)) }
                }
                .disabled(speakers.volume == nil)

                Text("\(Int(sliderVolume))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 24, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text("Sub")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Sub Out", selection: Binding(
                    get: { speakers.subOut ?? .medium },
                    set: { speakers.setSubOut($0) }
                )) {
                    ForEach(EdifierSubOutLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(speakers.subOut == nil)
            }

            if speakers.state == .unavailable {
                HStack {
                    Text("Not reachable. Close the Edifier app on your phone.")
                        .font(.caption2)
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
        case .idle: return speakers.volume == nil ? "Idle" : "Standby"
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
