//
//  MediaKeyMonitor.swift
//  LGTV Companion Shared
//
//  Intercepts the keyboard volume keys (F11/F12 / volume wheel) so they
//  control the TV instead of the Mac's audio output.
//

import Foundation
import AppKit
import CoreGraphics

public enum MediaKeyEvent {
    case volumeUp
    case volumeDown
    case mute
}

public final class MediaKeyMonitor {
    /// Returns whether the key was actually routed to a TV. When it returns
    /// false (e.g. no enabled device), the key is NOT swallowed so the Mac's
    /// own volume control keeps working.
    public var onMediaKey: ((MediaKeyEvent) -> Bool)?

    /// True when the CGEventTap is active (events are swallowed, the Mac's
    /// own volume OSD does not appear). False = passive fallback.
    public private(set) var isUsingEventTap = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?

    // NX_KEYTYPE_* constants (IOKit/hidsystem/ev_keymap.h)
    private static let keySoundUp: Int = 0
    private static let keySoundDown: Int = 1
    private static let keyMute: Int = 7
    private static let nxSysdefined: UInt32 = 14 // NX_SYSDEFINED event type

    public init() {}

    deinit { stop() }

    public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt asking the user to grant Accessibility
    /// permission (System Settings → Privacy & Security → Accessibility).
    public static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// - Parameter allowPassiveFallback: when false and Accessibility
    ///   permission is missing, does nothing at all. This avoids macOS
    ///   showing a permission prompt on every app launch — installing a
    ///   global event monitor without permission triggers the prompt.
    public func start(allowPassiveFallback: Bool = false) {
        stop()

        if Self.hasAccessibilityPermission {
            startEventTap()
        }

        if eventTap == nil && allowPassiveFallback {
            // Passive fallback: we still see the keys, but cannot swallow
            // them — the Mac volume OSD will also react.
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
                _ = self?.process(event)
            }
            isUsingEventTap = false
        }
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        isUsingEventTap = false
    }

    // MARK: - Event Tap

    private func startEventTap() {
        let mask = CGEventMask(1 << Self.nxSysdefined)

        let callback: CGEventTapCallBack = { _, type, cgEvent, refcon in
            guard let refcon = refcon else {
                return Unmanaged.passUnretained(cgEvent)
            }
            let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

            // Re-enable if the system disabled the tap (timeout)
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(cgEvent)
            }

            if let nsEvent = NSEvent(cgEvent: cgEvent), monitor.process(nsEvent) {
                return nil // swallow — Mac OSD won't show
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isUsingEventTap = true
        }
    }

    /// Returns true if the event was one of our media keys (and handled).
    private func process(_ event: NSEvent) -> Bool {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else {
            return false
        }

        let data1 = event.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A

        // Track per-key whether the matching key-down was routed to a TV, so
        // the paired key-up is swallowed iff its key-down was — keeping the
        // key event consistent for the system when we don't handle it.
        switch keyCode {
        case Self.keySoundUp:
            if isKeyDown { lastDownRouted = onMediaKey?(.volumeUp) ?? false }
            return lastDownRouted
        case Self.keySoundDown:
            if isKeyDown { lastDownRouted = onMediaKey?(.volumeDown) ?? false }
            return lastDownRouted
        case Self.keyMute:
            if isKeyDown { lastDownRouted = onMediaKey?(.mute) ?? false }
            return lastDownRouted
        default:
            return false
        }
    }

    /// Whether the most recent media-key *down* was routed to a TV. Used to
    /// swallow the paired key-up consistently.
    private var lastDownRouted = false
}
