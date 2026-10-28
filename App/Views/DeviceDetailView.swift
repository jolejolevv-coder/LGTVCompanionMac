//
//  DeviceDetailView.swift
//  LGTV Companion
//
//  Detailed view for configuring a device
//

import LGTVCompanionShared
import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @Binding var device: WebOSDevice
    @State private var isPairing = false
    @State private var isTesting = false
    @State private var isDetecting = false
    @State private var selectedWOLMethod: WakeOnLANMethod = .broadcast
    /// The device as last written to the manager's store. Autosave compares
    /// against it so only a real edit is saved.
    @State private var lastSaved: WebOSDevice
    @State private var autosaveTask: Task<Void, Never>?
    /// Success messages shown in the row of the action, cleared after a while.
    @State private var statusLines: [StatusRow: StatusLine] = [:]

    /// Wait this long after the last edit before saving, so typing an IP
    /// address does not save (and reconnect) on every key.
    private static let autosaveDelaySeconds: TimeInterval = 0.5
    /// How long a success message stays next to its button.
    private static let statusDisplaySeconds: TimeInterval = 4

    private enum StatusRow: Hashable {
        case macInput, connectionTest, pairing
    }

    private struct StatusLine: Equatable {
        let id = UUID()
        let text: String
    }

    init(device: Binding<WebOSDevice>) {
        _device = device
        _lastSaved = State(initialValue: device.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            Form {
                Section("TV") {
                    deviceInfoSection
                }

                Section {
                    automationSettingsSection
                } header: {
                    Text("Automation")
                } footer: {
                    Text("Screen-off keeps the TV running so it resumes at once. With a Mac input set, the TV stays on while it shows another input.")
                }

                Section("Network") {
                    networkSettingsSection
                }

                Section("Actions") {
                    actionButtonsSection
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: device) { _, _ in
            scheduleAutosave()
        }
        .onDisappear {
            // Selecting another TV within the delay must not lose the edit.
            saveNow()
        }
        .task {
            await deviceManager.refreshStatus(for: device)
        }
    }

    // MARK: - Header

    private var status: DeviceStatus? { deviceManager.deviceStatuses[device.id] }

    private var headerBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "tv")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(headerStatusColor)
                        .frame(width: 7, height: 7)
                    Text(headerStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(device.ipAddress)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Quick actions
            HStack(spacing: 8) {
                Button {
                    quickAction { try await deviceManager.screenOn(device) }
                } label: {
                    Label("Screen On", systemImage: "tv")
                }
                .help("Turn the screen on")

                Button {
                    quickAction { try await deviceManager.screenOff(device) }
                } label: {
                    Label("Screen Off", systemImage: "tv.slash")
                }
                .help("Turn the screen off (TV stays on)")
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.regular)
            .disabled(!device.enabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var headerStatusColor: Color {
        guard let status = status else { return .gray }
        if status.isScreenOn { return .green }
        if status.isReachable { return .orange }
        return .gray
    }

    private var headerStatusText: String {
        guard let status = status else { return "Status unknown" }
        return status.powerState ?? "Offline"
    }

    private func quickAction(_ action: @escaping () async throws -> Void) {
        Task { try? await action() }
    }

    // MARK: - Sections

    private var deviceInfoSection: some View {
        Group {
            TextField("Name", text: $device.name)

            Toggle("Enabled", isOn: $device.enabled)
                .help("Enable or disable this TV")

            LabeledContent("Pairing") {
                if device.pairingKey != nil {
                    Label("Paired", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Not paired", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }
    
    private var automationSettingsSection: some View {
        Group {
            Toggle("Follow Mac sleep and wake", isOn: $device.autoManage)
                .help("Turns the TV off when the Mac sleeps or shuts down, and back on when it wakes")

            Toggle("Use screen-off instead of power-off", isOn: $device.useScreenOff)
                .help("The picture turns off but the TV stays on and resumes instantly. Recommended for monitor use.")

            LabeledContent("Mac input") {
                HStack(spacing: 8) {
                    if isDetecting {
                        ProgressView().controlSize(.small)
                    }
                    statusLabel(for: .macInput)
                    Text(device.macInputAppId.map(Self.inputLabel) ?? "Not set")
                        .foregroundStyle(.secondary)
                    Button(device.macInputAppId == nil ? "Detect" : "Re-detect") {
                        detectMacInput()
                    }
                    .help("Press while the TV shows your Mac")
                    .disabled(isDetecting || !device.enabled)
                    if device.macInputAppId != nil {
                        Button("Clear") {
                            device.macInputAppId = nil
                            saveNow()
                        }
                        .disabled(isDetecting)
                    }
                }
            }

        }
    }

    private var networkSettingsSection: some View {
        Group {
            TextField("IP Address", text: $device.ipAddress)
                .multilineTextAlignment(.trailing)

            TextField("MAC Address", text: $device.macAddress)
                .multilineTextAlignment(.trailing)

            Picker("Wake-on-LAN", selection: $selectedWOLMethod) {
                ForEach(WakeOnLANMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .help(selectedWOLMethod.description)

            if !WakeOnLAN.isValidIPAddress(device.ipAddress) {
                Label("Invalid IP address format", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !WakeOnLAN.isValidMacAddress(device.macAddress) {
                Label("Invalid MAC address format", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !hasValidNetworkSettings {
                Text("Changes are saved once the IP and MAC address are valid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtonsSection: some View {
        Group {
            LabeledContent("Connection test") {
                HStack(spacing: 8) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    statusLabel(for: .connectionTest)
                    Button("Power On") { testPowerOn() }
                        .disabled(isTesting || !device.enabled)
                    Button("Power Off") { testPowerOff() }
                        .disabled(isTesting || !device.enabled)
                }
            }

            LabeledContent("Pairing") {
                HStack(spacing: 8) {
                    if isPairing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    statusLabel(for: .pairing)
                    pairButton
                }
            }
        }
    }

    private var pairButton: some View {
        Button(isPairing ? "Pairing…" : (device.pairingKey != nil ? "Pair Again" : "Pair TV")) {
            pairDevice()
        }
        .disabled(isPairing || !device.enabled)
    }

    // MARK: - Autosave

    private var hasValidNetworkSettings: Bool {
        WakeOnLAN.isValidIPAddress(device.ipAddress) && WakeOnLAN.isValidMacAddress(device.macAddress)
    }

    /// True if anything but the pairing key differs from the stored device.
    /// The key is written by the manager after pairing; saving because of it
    /// would drop the connection that was just built.
    private var hasUnsavedChanges: Bool {
        var current = device
        var stored = lastSaved
        current.pairingKey = nil
        stored.pairingKey = nil
        return current != stored
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.autosaveDelaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    /// Writes the device to the store if it changed and IP and MAC are valid.
    /// An invalid edit stays in the form and is saved once it becomes valid.
    private func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard hasUnsavedChanges, hasValidNetworkSettings else { return }
        lastSaved = device
        deviceManager.updateDevice(device)
    }

    // MARK: - Status lines

    @ViewBuilder
    private func statusLabel(for row: StatusRow) -> some View {
        if let line = statusLines[row] {
            Label(line.text, systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.callout)
                .foregroundStyle(.green)
                .transition(.opacity)
        }
    }

    /// Shows `text` in the row for a few seconds.
    private func showStatus(_ text: String, in row: StatusRow) {
        let line = StatusLine(text: text)
        withAnimation { statusLines[row] = line }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.statusDisplaySeconds * 1_000_000_000))
            // Only clear our own message, not a newer one.
            if statusLines[row] == line {
                withAnimation { statusLines[row] = nil }
            }
        }
    }

    /// For failures the user has to act on. Titled by what failed.
    private func showFailure(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Actions

    private func pairDevice() {
        isPairing = true
        let target = device

        Task {
            do {
                // Returns after the TV confirmed the pairing (accept the
                // prompt on the TV if it appears).
                try await deviceManager.pairDevice(target)
                await MainActor.run {
                    isPairing = false
                    showStatus("Paired", in: .pairing)
                }
            } catch {
                await MainActor.run {
                    isPairing = false
                    showFailure("Unable to Pair",
                                message: "\(error.localizedDescription). Make sure the TV is on and on the same network as this Mac, then accept the prompt on the TV.")
                }
            }
        }
    }

    private func testPowerOn() {
        isTesting = true
        let target = device
        let method = selectedWOLMethod

        Task {
            do {
                try await deviceManager.powerOnDevice(target, method: method)
                await MainActor.run {
                    isTesting = false
                    showStatus("Power on sent", in: .connectionTest)
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    showFailure("Unable to Power On",
                                message: "\(error.localizedDescription). Check the MAC address and that the TV and this Mac are on the same network.")
                }
            }
        }
    }

    private func testPowerOff() {
        isTesting = true
        let target = device

        Task {
            do {
                try await deviceManager.powerOffDevice(target)
                await MainActor.run {
                    isTesting = false
                    showStatus("Power off sent", in: .connectionTest)
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    showFailure("Unable to Reach TV",
                                message: "\(error.localizedDescription). Check that the TV is on and reachable at \(target.ipAddress).")
                }
            }
        }
    }

    private func detectMacInput() {
        isDetecting = true
        let target = device

        Task {
            do {
                let appId = try await deviceManager.readForegroundInput(for: target)
                await MainActor.run {
                    isDetecting = false
                    if let appId = appId {
                        device.macInputAppId = appId
                        saveNow()
                        showStatus("Set to \(Self.inputLabel(appId))", in: .macInput)
                    } else {
                        showFailure("Unable to Detect Mac Input",
                                    message: "The TV didn't report a current input. Make sure it's on and showing your Mac, then try again.")
                    }
                }
            } catch {
                await MainActor.run {
                    isDetecting = false
                    showFailure("Unable to Detect Mac Input",
                                message: "\(error.localizedDescription). Make sure the TV is on and reachable, then try again.")
                }
            }
        }
    }

    // MARK: - Helpers

    /// "com.webos.app.hdmi3" → "HDMI 3"; otherwise a cleaned-up id.
    static func inputLabel(_ appId: String) -> String {
        let prefix = "com.webos.app."
        guard appId.hasPrefix(prefix) else { return appId }
        let short = String(appId.dropFirst(prefix.count)) // e.g. "hdmi3"
        if short.lowercased().hasPrefix("hdmi") {
            let number = short.dropFirst(4)
            return number.isEmpty ? "HDMI" : "HDMI \(number)"
        }
        return short.uppercased()
    }
}
