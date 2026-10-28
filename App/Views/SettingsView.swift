//
//  SettingsView.swift
//  LGTV Companion
//
//  Application settings view
//

import Combine
import LGTVCompanionShared
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    
    @State private var userIdleEnabled: Bool
    @State private var userIdleTimeout: Double
    @State private var launchAtLogin = false
    /// Why the last launch-at-login change failed, shown under the toggle.
    @State private var launchAtLoginError: String?
    /// The login item is registered but macOS waits for the user's approval.
    @State private var launchAtLoginNeedsApproval = false
    @State private var mediaKeysEnabled = false
    @State private var confirmingReset = false
    /// The tab shown when the window opens: the one used last.
    @AppStorage("lgtvcompanion.ui.settingsTab") private var selectedTab = SettingsTab.general.rawValue

    /// Apps currently holding a display-sleep assertion. Refreshed live while
    /// the settings window is open so a starting video shows up on its own.
    @State private var displaySleepApps: [AssertingApp] = []

    private static let windowWidth: CGFloat = 520
    private static let idleTimeoutRange: ClosedRange<Double> = 60...3600
    private static let idleTimeoutStep: Double = 60
    private static let aboutIconSize: CGFloat = 96
    private static let assertionRefreshSeconds: TimeInterval = 3
    private let assertionRefreshTimer = Timer.publish(
        every: assertionRefreshSeconds,
        tolerance: TimerTolerance.tolerance(for: assertionRefreshSeconds),
        on: .main, in: .common
    ).autoconnect()

    init() {
        // Initialize from device manager will happen in onAppear
        _userIdleEnabled = State(initialValue: false)
        _userIdleTimeout = State(initialValue: 300)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            generalSettingsTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general.rawValue)

            automationSettingsTab
                .tabItem {
                    Label("Automation", systemImage: "bolt")
                }
                .tag(SettingsTab.automation.rawValue)

            SpeakerSettingsTab(speakers: DeviceManager.shared.speakers,
                               automation: DeviceManager.shared.speakerAutomation)
                .tabItem {
                    Label("Speakers", systemImage: "hifispeaker.2")
                }
                .tag(SettingsTab.speakers.rawValue)

            NightModeSettingsTab(speakers: DeviceManager.shared.speakers,
                                 automation: DeviceManager.shared.speakerAutomation)
                .tabItem {
                    Label("Night Mode", systemImage: "moon")
                }
                .tag(SettingsTab.nightMode.rawValue)

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about.rawValue)
        }
        // The height follows the content of the selected tab.
        .frame(width: Self.windowWidth)
        .onAppear {
            loadSettings()
        }
    }

    // MARK: - Tabs
    
    private var generalSettingsTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .accessibilityIdentifier(AccessibilityID.Settings.launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if launchAtLoginNeedsApproval {
                    Text("macOS needs your approval before the app can start at login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }

                LabeledContent("Power event monitoring",
                               value: deviceManager.isMonitoringPowerEvents ? "On" : "Off")
            } header: {
                Text("Startup")
            } footer: {
                Text("The app watches sleep, wake and shutdown to switch the TVs.")
            }
            
            Section {
                Toggle("Volume keys control the TV and speakers", isOn: $mediaKeysEnabled)
                    .accessibilityIdentifier(AccessibilityID.Settings.volumeKeys)
                    .onChange(of: mediaKeysEnabled) { _, newValue in
                        // Only act on a real user toggle. loadSettings() also
                        // moves this value (false → stored), which would
                        // otherwise re-trigger the Accessibility prompt on
                        // every Settings open.
                        guard newValue != deviceManager.mediaKeysEnabled else { return }
                        deviceManager.setMediaKeysEnabled(newValue)
                    }

                Toggle("Adjust the Mac's volume when the TV can't", isOn: Binding(
                    get: { deviceManager.softwareVolumeEnabled },
                    set: { deviceManager.setSoftwareVolumeEnabled($0) }
                ))
                .accessibilityIdentifier(AccessibilityID.Settings.softwareVolume)
            } header: {
                Text("Volume Keys")
            } footer: {
                Text("On a TV output with a fixed level, such as optical, the keys lower the Mac's sound instead.")
            }

            PermissionsSection()

            Section {
                Button("Reset All Settings…", role: .destructive) {
                    confirmingReset = true
                }
                .confirmationDialog("Reset all settings?", isPresented: $confirmingReset,
                                    titleVisibility: .visible) {
                    // No keyboard shortcut and not the default: Return must
                    // not trigger it.
                    Button("Reset All Settings", role: .destructive) {
                        resetSettings()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes all TVs and their pairing keys and resets every option, including the speakers. It cannot be undone. Launch at login is not changed.")
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Removes all TVs and puts every option back to its default.")
            }
        }
        .formStyle(.grouped)
    }

    private var automationSettingsTab: some View {
        Form {
            Section {
                Toggle("Switch TVs off when the Mac is idle", isOn: $userIdleEnabled)
                    .accessibilityIdentifier(AccessibilityID.Settings.userIdle)
                    .onChange(of: userIdleEnabled) { _, newValue in
                        updateUserIdleSettings()
                    }

                if userIdleEnabled {
                    LabeledContent("Idle timeout") {
                        Text(formatTimeout(userIdleTimeout))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $userIdleTimeout, in: Self.idleTimeoutRange, step: Self.idleTimeoutStep) {
                        Text("Idle timeout")
                    }
                    .labelsHidden()
                    .accessibilityIdentifier(AccessibilityID.Settings.idleTimeout)
                    .onChange(of: userIdleTimeout) { _, _ in
                        updateUserIdleSettings()
                    }
                }
            } header: {
                Text("User Idle Detection")
            } footer: {
                Text("The TVs switch off after this much inactivity and on again when you return.")
            }

            if userIdleEnabled {
                Section {
                    let apps = keepAwakeApps()
                    if apps.isEmpty {
                        Text("No app is keeping the screen awake right now. Start a video and it appears here.")
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
                        }
                    }
                } header: {
                    Text("Keep TV On During Playback")
                } footer: {
                    Text("Enabled apps keep the TV on while they play video, even without mouse or keyboard activity.")
                }
            }

            Section {
                Label("System sleep and wake", systemImage: "powersleep")
                Label("Display sleep and wake", systemImage: "display")
                Label("Shutdown and restart", systemImage: "power")
                Label("Display configuration changes", systemImage: "rectangle.3.group")
            } header: {
                Text("Monitored Events")
            } footer: {
                Text("These apply to TVs that follow the Mac's sleep and wake.")
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
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Self.aboutIconSize, height: Self.aboutIconSize)
            
            Text("LGTV Companion")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version \(AppInfo.version)")
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
            
            HStack(spacing: 16) {
                Link(destination: AppInfo.repositoryURL) {
                    Label("GitHub", systemImage: "link")
                }
                
                Link(destination: AppInfo.issuesURL) {
                    Label("Report Issue", systemImage: "exclamationmark.bubble")
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Helpers

    private func loadSettings() {
        userIdleEnabled = deviceManager.userIdleEnabled
        userIdleTimeout = deviceManager.userIdleTimeout
        refreshLaunchAtLogin()
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
        // Also fires when refreshLaunchAtLogin() moves the toggle (initial
        // load, rollback). Nothing to do when it already matches the system.
        guard enabled != LaunchAtLogin.isRegistered else { return }

        launchAtLoginError = nil
        do {
            try LaunchAtLogin.setRegistered(enabled)
        } catch {
            launchAtLoginError = "Could not change launch at login: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    /// Takes the toggle from the real status, so a failed change rolls back.
    private func refreshLaunchAtLogin() {
        launchAtLogin = LaunchAtLogin.isRegistered
        launchAtLoginNeedsApproval = LaunchAtLogin.status == .requiresApproval
    }
    
    private func resetSettings() {
        deviceManager.resetAllSettings()
        // The form keeps its own copies of some values.
        loadSettings()
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
    // when launched as a bare SwiftPM executable, register() throws.
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Registered, or registered and waiting for the user's approval in
    /// System Settings. Both count as "on" for the toggle.
    static var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    static func setRegistered(_ registered: Bool) throws {
        if registered {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// The tabs of the Settings window. The raw value is what is remembered.
enum SettingsTab: String {
    case general, automation, speakers, nightMode, about
}
