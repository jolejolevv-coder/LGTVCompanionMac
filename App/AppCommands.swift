//
//  AppCommands.swift
//  LGTV Companion
//
//  Menu bar commands (File, TV, Speakers). They are visible while the app
//  has a window open and the Dock icon.
//
//  Shortcuts avoid the ones macOS and standard menus use: ⌘N and ⌘R are the
//  usual "new" and "refresh", everything else is ⌥⌘ or ⇧⌘N.
//

import LGTVCompanionShared
import SwiftUI

/// Which sheet of the main window a menu command wants.
enum MainWindowSheet {
    case scan
    case add
}

/// Connects menu commands with the main window: the sheet a command asks
/// for, and which TV is selected in the sidebar.
@MainActor
final class MainWindowRouter: ObservableObject {
    static let shared = MainWindowRouter()

    /// Set by a command, taken (and cleared) by the main window.
    @Published var pendingSheet: MainWindowSheet?
    /// Mirrors the sidebar selection.
    @Published var selectedDeviceID: UUID?

    /// Opens the main window and asks it to show `sheet`. The window may not
    /// exist yet, so the request waits in `pendingSheet`.
    func show(_ sheet: MainWindowSheet, openWindow: OpenWindowAction) {
        pendingSheet = sheet
        MainWindowGate.shared.open(using: openWindow)
    }

    /// The TV a TV menu command acts on: the selected one, otherwise the
    /// first enabled one.
    func targetDevice(in manager: DeviceManager) -> WebOSDevice? {
        let enabled = manager.devices.filter(\.enabled)
        if let id = selectedDeviceID, let selected = enabled.first(where: { $0.id == id }) {
            return selected
        }
        return enabled.first
    }
}

/// File > Add TV… (⌘N), in place of the document based "New".
struct NewTVCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add TV…") {
                MainWindowRouter.shared.show(.add, openWindow: openWindow)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

/// The "TV" menu.
struct TVCommands: Commands {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var router: MainWindowRouter
    @Environment(\.openWindow) private var openWindow

    private var target: WebOSDevice? { router.targetDevice(in: deviceManager) }

    var body: some Commands {
        CommandMenu("TV") {
            Button("Scan for TVs…") {
                router.show(.scan, openWindow: openWindow)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Add TV…") {
                router.show(.add, openWindow: openWindow)
            }

            Divider()

            Button("Refresh Status") {
                Task { await deviceManager.refreshAllStatuses() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(deviceManager.devices.isEmpty)

            Divider()

            Button("Screen On") {
                run { try await deviceManager.screenOn($0) }
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(target == nil)

            Button("Screen Off") {
                run { try await deviceManager.screenOff($0) }
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(target == nil)

            Divider()

            Button("Power On") {
                run {
                    try await deviceManager.powerOnDevice($0)
                    await deviceManager.refreshStatus(for: $0)
                }
            }
            .keyboardShortcut("3", modifiers: [.command, .option])
            .disabled(target == nil)

            Button("Power Off") {
                run { try await deviceManager.fullPowerOff($0) }
            }
            .keyboardShortcut("4", modifiers: [.command, .option])
            .disabled(target == nil)
        }
    }

    /// Runs a TV command on the target. A failure is kept in
    /// `deviceManager.lastError` and shown in the menu bar panel.
    private func run(_ action: @escaping (WebOSDevice) async throws -> Void) {
        guard let device = target else { return }
        Task { try? await action(device) }
    }
}

/// The "Speakers" menu.
struct SpeakerCommands: Commands {
    @ObservedObject var speakers: EdifierSpeakerController
    @ObservedObject var automation: SpeakerAutomation

    var body: some Commands {
        CommandMenu("Speakers") {
            Toggle("Night Mode", isOn: Binding(
                get: { automation.nightModeActive },
                set: { automation.setNightMode($0) }
            ))
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(!speakers.isEnabled)
        }
    }
}
