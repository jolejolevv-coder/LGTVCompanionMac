//
//  SettingsView.swift
//  LGTV Companion
//
//  Application settings view
//

import LGTVCompanionShared
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    
    @State private var userIdleEnabled: Bool
    @State private var userIdleTimeout: Double
    @State private var launchAtLogin = false
    @State private var mediaKeysEnabled = false

    /// Apps currently holding a display-sleep assertion. Refreshed live while
    /// the settings window is open so a starting video shows up on its own.
    @State private var displaySleepApps: [AssertingApp] = []

    private let assertionRefreshTimer = Timer.publish(
        every: 3, on: .main, in: .common
    ).autoconnect()

    init() {
        // Initialize from device manager will happen in onAppear
        _userIdleEnabled = State(initialValue: false)
        _userIdleTimeout = State(initialValue: 300)
    }
    
    var body: some View {
        TabView {
            generalSettingsTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            automationSettingsTab
                .tabItem {
                    Label("Automation", systemImage: "bolt")
                }
            
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 550, height: 400)
        .onAppear {
            loadSettings()
        }
    }
    
    // MARK: - Tabs
    
    private var generalSettingsTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .tint(.green)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }
                
                Toggle("Enable power event monitoring", isOn: .constant(deviceManager.isMonitoringPowerEvents))
                    .disabled(true)
                    .help("Monitoring is automatically enabled when devices are set to auto-manage")
            } header: {
                Text("Startup")
            }
            
            Section {
                Toggle("Keyboard volume keys control the TV", isOn: $mediaKeysEnabled)
                    .tint(.green)
                    .onChange(of: mediaKeysEnabled) { _, newValue in
                        // Only act on a real user toggle. loadSettings() also
                        // moves this value (false → stored), which would
                        // otherwise re-trigger the Accessibility prompt on
                        // every Settings open.
                        guard newValue != deviceManager.mediaKeysEnabled else { return }
                        deviceManager.setMediaKeysEnabled(newValue)
                    }

                Text("Requires Accessibility permission (System Settings → Privacy & Security → Accessibility) so the Mac's own volume display doesn't react too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Volume Keys")
            }

            Section {
                Button("Reset All Settings") {
                    resetSettings()
                }
                .foregroundStyle(.red)
            } header: {
                Text("Advanced")
            }
        }
        .formStyle(.grouped)
    }

    private var automationSettingsTab: some View {
        Form {
            Section {
                Toggle("Enable User Idle Mode", isOn: $userIdleEnabled)
                    .tint(.green)
                    .onChange(of: userIdleEnabled) { _, newValue in
                        updateUserIdleSettings()
                    }
                
                if userIdleEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Idle timeout:")
                            Spacer()
                            Text(formatTimeout(userIdleTimeout))
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $userIdleTimeout, in: 60...3600, step: 60)
                            .onChange(of: userIdleTimeout) { _, _ in
                                updateUserIdleSettings()
                            }
                        
                        Text("TVs will turn off after this period of inactivity and turn back on when you return")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 20)
                }
            } header: {
                Text("User Idle Detection")
            }

            if userIdleEnabled {
                Section {
                    let apps = keepAwakeApps()
                    if apps.isEmpty {
                        Text("No app is keeping the screen awake right now. Start a video (e.g. YouTube) and it will appear here so you can enable it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(apps) { app in
                            Toggle(isOn: Binding(
                                get: { deviceManager.isAppAllowed(app.bundleID) },
                                set: { deviceManager.setAppAllowed(app, allowed: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                    if !liveBundleIDs.contains(app.bundleID) {
                                        Text("not playing right now")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.green)
                        }
                    }
                } header: {
                    Text("Keep TV On During Playback")
                } footer: {
                    Text("Enabled apps keep the TV on while they play video, even without mouse or keyboard activity. Apps holding the screen awake right now appear automatically.")
                        .font(.caption2)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("System Sleep/Wake", systemImage: "powersleep")
                    Label("Display Sleep/Wake", systemImage: "display")
                    Label("System Shutdown/Restart", systemImage: "power")
                    Label("Display Configuration Changes", systemImage: "rectangle.3.group")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Monitored Events")
            } footer: {
                Text("These events are automatically monitored for devices with 'Automatically manage' enabled")
                    .font(.caption2)
            }
        }
        .formStyle(.grouped)
        .onReceive(assertionRefreshTimer) { _ in
            if userIdleEnabled {
                displaySleepApps = deviceManager.currentDisplaySleepApps()
            }
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 20) {
            if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "tv.and.hifispeaker.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)
            }
            
            Text("LGTV Companion")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Text("Control your LG WebOS TV from your Mac")
                    .multilineTextAlignment(.center)

                Text("Made by Nahobino")
                    .font(.subheadline.weight(.medium))

                Text("Inspired by the original Windows application by Jörgen Persson")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://github.com")!) {
                    Label("GitHub", systemImage: "link")
                }
                
                Link(destination: URL(string: "https://github.com")!) {
                    Label("Report Issue", systemImage: "exclamationmark.bubble")
                }
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    
    private func loadSettings() {
        userIdleEnabled = deviceManager.userIdleEnabled
        userIdleTimeout = deviceManager.userIdleTimeout
        launchAtLogin = LaunchAtLogin.isEnabled
        mediaKeysEnabled = deviceManager.mediaKeysEnabled
        displaySleepApps = deviceManager.currentDisplaySleepApps()
    }

    /// Bundle IDs of apps that are playing right now (live assertion holders).
    private var liveBundleIDs: Set<String> {
        Set(displaySleepApps.map { $0.bundleID })
    }

    /// Union of apps playing right now and apps already on the allowlist
    /// (so a remembered choice stays visible even when the app isn't playing).
    private func keepAwakeApps() -> [AssertingApp] {
        var seen = Set<String>()
        var combined: [AssertingApp] = []
        for app in displaySleepApps + deviceManager.assertionAllowlist {
            if seen.insert(app.bundleID).inserted {
                combined.append(app)
            }
        }
        return combined.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    
    private func updateUserIdleSettings() {
        deviceManager.updateUserIdleSettings(
            enabled: userIdleEnabled,
            timeout: userIdleTimeout
        )
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLogin.isEnabled = enabled
    }
    
    private func resetSettings() {
        let alert = NSAlert()
        alert.messageText = "Reset All Settings?"
        alert.informativeText = "This will remove all devices and reset all settings to defaults. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Clear all devices
            for device in deviceManager.devices {
                deviceManager.removeDevice(device)
            }
            
            // Reset settings
            userIdleEnabled = false
            userIdleTimeout = 300
            updateUserIdleSettings()

            // Clear the keep-awake allowlist too.
            for app in deviceManager.assertionAllowlist {
                deviceManager.setAppAllowed(app, allowed: false)
            }
            displaySleepApps = deviceManager.currentDisplaySleepApps()
        }
    }
    
    private func formatTimeout(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }
}

// MARK: - Launch at Login Helper

struct LaunchAtLogin {
    // Modern SMAppService API (macOS 13+). Registers the app itself as a
    // login item. NOTE: only works when running from a real .app bundle —
    // when launched as a bare SwiftPM executable this is a no-op.
    static var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at login change failed: \(error)")
            }
        }
    }
}
