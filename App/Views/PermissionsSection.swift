//
//  PermissionsSection.swift
//  LGTV Companion
//
//  Settings section that shows which macOS permissions the app has and
//  opens the matching pane of System Settings.
//

import AppKit
import CoreBluetooth
import LGTVCompanionShared
import SwiftUI

/// Reads the permission states. Polls while the Settings window is on screen
/// and something is missing, so the row turns green soon after the user
/// flips the switch in System Settings.
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published private(set) var accessibilityGranted = MediaKeyMonitor.hasAccessibilityPermission
    @Published private(set) var bluetooth = CBManager.authorization

    /// The Settings window; polling pauses while it is hidden.
    weak var window: NSWindow?

    private static let pollSeconds: TimeInterval = 2
    private var timer: Timer?

    /// System Audio Recording cannot be queried, so it is not part of this.
    /// Bluetooth that was never asked is not missing: the prompt comes with
    /// the speaker feature.
    var somethingMissing: Bool {
        !accessibilityGranted || bluetooth == .denied || bluetooth == .restricted
    }

    func refresh() {
        let accessibility = MediaKeyMonitor.hasAccessibilityPermission
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        let current = CBManager.authorization
        if current != bluetooth { bluetooth = current }
    }

    /// Reads the states now and keeps reading them while something is missing.
    func startPolling() {
        refresh()
        guard timer == nil, somethingMissing else { return }

        let timer = Timer(timeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = TimerTolerance.tolerance(for: Self.pollSeconds)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard window?.isVisible ?? true else { return }
        refresh()
        if !somethingMissing { stopPolling() }
    }
}

struct PermissionsSection: View {
    @StateObject private var monitor = PermissionMonitor()

    private static let accessibilityPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    private static let audioCapturePane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
    private static let bluetoothPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
    private static let systemSettingsApp = "x-apple.systempreferences:"

    var body: some View {
        Section {
            // The monitor hooks sit on the first row: one view that appears
            // and disappears with the section.
            row("Accessibility", state: accessibilityState, pane: Self.accessibilityPane)
                .background(WindowAccessor { monitor.window = $0 })
                .onAppear { monitor.startPolling() }
                .onDisappear { monitor.stopPolling() }
                // Coming back from System Settings.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    monitor.startPolling()
                }
            row("System Audio Recording", state: .text("Granted when macOS asks"),
                pane: Self.audioCapturePane)
            row("Bluetooth", state: bluetoothState, pane: Self.bluetoothPane)
        } header: {
            Text("Permissions")
        } footer: {
            Text("Accessibility keeps the volume keys from also changing the Mac's volume. System Audio Recording is for the Mac volume fallback, Bluetooth for the speakers.")
        }
    }

    // MARK: - Rows

    private enum RowState {
        case granted
        case missing(String)
        case text(String)
    }

    private var accessibilityState: RowState {
        monitor.accessibilityGranted ? .granted : .missing("Not granted")
    }

    private var bluetoothState: RowState {
        switch monitor.bluetooth {
        case .allowedAlways: return .granted
        case .notDetermined: return .text("Not asked yet")
        case .denied: return .missing("Denied")
        case .restricted: return .missing("Restricted")
        @unknown default: return .text("Unknown")
        }
    }

    private func row(_ title: String, state: RowState, pane: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                stateLabel(state)
                Button("Open System Settings…") { open(pane) }
            }
        }
    }

    @ViewBuilder
    private func stateLabel(_ state: RowState) -> some View {
        switch state {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .missing(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .text(let text):
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    /// Opens the pane; if macOS does not know it, opens System Settings itself.
    private func open(_ pane: String) {
        guard let url = URL(string: pane), NSWorkspace.shared.open(url) else {
            if let fallback = URL(string: Self.systemSettingsApp) {
                NSWorkspace.shared.open(fallback)
            }
            return
        }
    }
}
