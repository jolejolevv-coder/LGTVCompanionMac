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
    
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            Form {
                Section("Device") {
                    deviceInfoSection
                }

                Section("Automation") {
                    automationSettingsSection
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    deviceManager.updateDevice(device)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
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
                .tint(.green)
                .help("Enable or disable this device")

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
            Toggle(isOn: $device.autoManage) {
                Text("Follow Mac sleep & wake")
                Text("Turns the TV off when the Mac sleeps or shuts down, and back on when it wakes.")
            }
            .tint(.green)

            Toggle(isOn: $device.useScreenOff) {
                Text("Use screen-off instead of power-off")
                Text("The picture turns off but the TV stays on — it resumes instantly without rebooting. Recommended for monitor use.")
            }
            .tint(.green)

            LabeledContent("Mac input") {
                HStack(spacing: 8) {
                    if isDetecting {
                        ProgressView().controlSize(.small)
                    }
                    Text(device.macInputAppId.map(Self.inputLabel) ?? "Not set")
                        .foregroundStyle(.secondary)
                    Button(device.macInputAppId == nil ? "Detect" : "Re-detect") {
                        detectMacInput()
                    }
                    .disabled(isDetecting || !device.enabled)
                    if device.macInputAppId != nil {
                        Button("Clear") {
                            device.macInputAppId = nil
                            deviceManager.updateDevice(device)
                        }
                        .disabled(isDetecting)
                    }
                }
            }

            Text("While set, the TV won't auto power-off whenever it's showing another input (e.g. a console on a different HDMI). Press Detect while the TV is showing your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    Button("Power On") { testPowerOn() }
                        .disabled(isTesting || !device.enabled)
                    Button("Power Off") { testPowerOff() }
                        .disabled(isTesting || !device.enabled)
                }
            }

            LabeledContent("Pairing") {
                Button(isPairing ? "Pairing…" : (device.pairingKey != nil ? "Pair Again" : "Pair Device")) {
                    pairDevice()
                }
                .disabled(isPairing || !device.enabled)
            }
        }
    }
    
    // MARK: - Actions
    
    private func pairDevice() {
        isPairing = true
        
        Task {
            do {
                let client = await MainActor.run { deviceManager.getClient(for: device) }
                try await client.connect()
                // register() returns only after the TV confirmed the pairing
                // (accept the prompt on the TV if it appears)
                try await client.register()

                await MainActor.run {
                    isPairing = false
                    showSuccess("Pairing successful!")
                }
            } catch {
                await MainActor.run {
                    isPairing = false
                    showError("Pairing failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func testPowerOn() {
        isTesting = true
        
        Task {
            do {
                try await deviceManager.powerOnDevice(device, method: selectedWOLMethod)
                
                await MainActor.run {
                    isTesting = false
                    showSuccess("Power on command sent successfully")
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    showError("Power on failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func testPowerOff() {
        isTesting = true
        
        Task {
            do {
                try await deviceManager.powerOffDevice(device)
                
                await MainActor.run {
                    isTesting = false
                    showSuccess("Power off command sent successfully")
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    showError("Power off failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func detectMacInput() {
        isDetecting = true

        Task {
            do {
                let appId = try await deviceManager.readForegroundInput(for: device)
                await MainActor.run {
                    isDetecting = false
                    if let appId = appId {
                        device.macInputAppId = appId
                        deviceManager.updateDevice(device)
                        showSuccess("Mac input set to \(Self.inputLabel(appId)).")
                    } else {
                        showError("The TV didn't report a current input. Make sure it's on and showing your Mac.")
                    }
                }
            } catch {
                await MainActor.run {
                    isDetecting = false
                    showError("Couldn't read the TV input: \(error.localizedDescription)")
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

    private func showSuccess(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Success"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}
