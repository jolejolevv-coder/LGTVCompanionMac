//
//  LGTVCompanionApp.swift
//  LGTV Companion
//
//  Main application entry point
//

import LGTVCompanionShared
import SwiftUI

@main
struct LGTVCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var deviceManager = DeviceManager.shared
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(deviceManager)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    deviceManager.startPowerEventMonitoring()
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About LGTV Companion") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "LGTV Companion",
                            .applicationVersion: "1.0.0",
                            .version: "macOS",
                            .credits: NSAttributedString(string: "Control your LG WebOS TV from your Mac\nMade by Nahobino")
                        ]
                    )
                }
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(deviceManager)
        }

        MenuBarExtra("LGTV Companion", systemImage: "tv") {
            MenuBarView()
                .environmentObject(deviceManager)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When run as a SwiftPM executable (no app bundle), the process
        // starts without a Dock icon or focus — fix that.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // App icon (Dock) — in a packaged .app, CFBundleIconFile in Info.plist handles
        // the icon automatically; this call is a belt-and-suspenders fallback and also
        // covers the `swift run` case. Bundle.main finds AppIcon.icns in Contents/Resources/;
        // Bundle.module would crash with fatalError() if its SPM bundle is missing.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }

        // Install the volume-key event tap at launch, independent of any
        // window. As a pure menu-bar app no window opens on start, so relying
        // on a view's .task meant the keys only began working after the user
        // first opened the menu. A short retry covers the brief window where
        // AXIsProcessTrusted() can still report false right after launch.
        DeviceManager.shared.ensureMediaKeyTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            DeviceManager.shared.ensureMediaKeyTap()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep app running in background
    }

    // MARK: - Shutdown handling
    //
    // System sleep is delayed via IOKit (PowerEventMonitor), but SHUTDOWN
    // kills processes before async work finishes. Holding termination with
    // .terminateLater gives us time to turn the TVs off first.

    private var didReplyTerminate = false
    private var isSystemShuttingDown = false
    private var powerOffObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Fires on logout/shutdown/restart BEFORE apps are asked to quit —
        // lets us tell a real shutdown apart from a plain app quit.
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.isSystemShuttingDown = true
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Plain app quit (⌘Q / menu) → just quit, leave the TV alone.
        guard isSystemShuttingDown else { return .terminateNow }

        let manager = DeviceManager.shared
        let targets = manager.devices.filter { $0.autoManage && $0.enabled }
        guard !targets.isEmpty else { return .terminateNow }

        Task {
            // Real shutdown → full power-off, not just screen-off
            await manager.powerOffManagedDevices(fullOff: true)
            await MainActor.run { self.replyTerminateOnce() }
        }

        // Safety net: never block quit/shutdown longer than 15 s
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.replyTerminateOnce()
        }

        return .terminateLater
    }

    private func replyTerminateOnce() {
        guard !didReplyTerminate else { return }
        didReplyTerminate = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up
    }
}
