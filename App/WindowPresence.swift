//
//  WindowPresence.swift
//  LGTV Companion
//
//  The app lives in the menu bar. Dock icon and app menu exist only while
//  the main window or the Settings window is open.
//

import AppKit
import SwiftUI

/// Switches between `.accessory` (menu bar only) and `.regular` (Dock icon,
/// app menu) depending on whether a window of the user is open.
@MainActor
final class WindowPresence {
    static let shared = WindowPresence()

    private var observers: [NSObjectProtocol] = []

    /// Starts watching windows. Call once at launch.
    func start() {
        guard observers.isEmpty else { return }
        NSApp.setActivationPolicy(.accessory)

        let center = NotificationCenter.default
        let becameKey = center.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(closing: nil) }
        }
        // The closing window still counts as visible while the notification
        // runs, so it is excluded by hand.
        let willClose = center.addObserver(forName: NSWindow.willCloseNotification,
                                           object: nil, queue: .main) { [weak self] note in
            let closing = note.object as? NSWindow
            MainActor.assumeIsolated { self?.refresh(closing: closing) }
        }
        let minimized = center.addObserver(forName: NSWindow.didMiniaturizeNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(closing: nil) }
        }
        observers = [becameKey, willClose, minimized]
    }

    /// Makes the app a regular one and brings it to the front. Used before a
    /// window is opened from the menu bar panel, where the app is not active.
    func activateForWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refresh(closing: NSWindow?) {
        let hasWindow = NSApp.windows.contains { $0 !== closing && Self.isUserWindow($0) }
        let target: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != target else { return }

        NSApp.setActivationPolicy(target)
        if target == .regular {
            // The policy change drops the key window; take focus back.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// A normal titled window that is on screen or in the Dock. Panels (the
    /// menu bar panel, alerts, the volume display), sheets and the main
    /// window while it is held back at launch do not count.
    private static func isUserWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled)
            && !(window is NSPanel)
            && window.sheetParent == nil
            && window.alphaValue > 0
            && (window.isVisible || window.isMiniaturized)
    }
}

/// SwiftUI opens a `Window` scene at launch. This app starts in the menu bar
/// without a window, so the first window that appears without a request from
/// the user is closed again before it can be seen.
@MainActor
final class MainWindowGate {
    static let shared = MainWindowGate()

    private var userRequestedWindow = false
    private var launchWindowHandled = false

    /// Call right before opening the main window on purpose.
    func userWillOpenWindow() {
        userRequestedWindow = true
    }

    func windowAttached(_ window: NSWindow) {
        guard !launchWindowHandled else { return }
        launchWindowHandled = true
        guard !userRequestedWindow else { return }

        // Invisible first, so neither the window nor the Dock icon flashes.
        window.alphaValue = 0
        DispatchQueue.main.async {
            window.close()
            window.alphaValue = 1
        }
    }

    /// Opens the main window and brings it to the front.
    func open(using openWindow: OpenWindowAction) {
        userWillOpenWindow()
        WindowPresence.shared.activateForWindow()
        openWindow(id: Self.windowID)
    }

    static let windowID = "main"
}

/// Hands the hosting `NSWindow` of a SwiftUI view to a closure.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = AccessorView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class AccessorView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window = window { onWindow?(window) }
        }
    }
}
