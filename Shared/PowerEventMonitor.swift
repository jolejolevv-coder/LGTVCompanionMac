//
//  PowerEventMonitor.swift
//  LGTV Companion Shared
//
//  Monitors macOS power events (sleep, wake, shutdown, etc.)
//

import Foundation
import AppKit
import IOKit
import IOKit.pwr_mgt

enum PowerEvent {
    case systemWillSleep
    case systemDidWake
    case systemWillShutdown
    case systemWillRestart
    case displayWillSleep
    case displayDidWake
}

// The kIOMessage* constants are C function-like macros
// (iokit_common_msg(0x...)) and are NOT imported into Swift.
// Values: 0xe0000000 (sys_iokit) | 0x0 (sub_iokit_common) | message.
private let kIOMessageCanSystemSleep: UInt32     = 0xe0000270
private let kIOMessageSystemWillSleep: UInt32    = 0xe0000280
private let kIOMessageSystemHasPoweredOn: UInt32 = 0xe0000300
private let kIOMessageSystemWillPowerOff: UInt32 = 0xe0000250
private let kIOMessageSystemWillRestart: UInt32  = 0xe0000310

class PowerEventMonitor {
    private var notifyPortRef: IONotificationPortRef?
    private var notifierObject: io_object_t = 0
    private var rootPort: io_connect_t = 0
    private var workspaceObservers: [NSObjectProtocol] = []

    /// Maximum time we delay system sleep while turning TVs off.
    /// macOS force-sleeps after ~30s regardless.
    private static let maxSleepDelay: TimeInterval = 20

    /// Handler receives the event and a completion closure.
    /// For `.systemWillSleep` the system sleep is DELAYED until the
    /// completion is called (or `maxSleepDelay` elapses) — this gives the
    /// TV power-off command time to actually reach the TV.
    /// For all other events the completion is a no-op; calling it is harmless.
    var onPowerEvent: ((PowerEvent, @escaping () -> Void) -> Void)?

    init() {
        setupPowerEventHandling()
    }

    deinit {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if notifierObject != 0 {
            IODeregisterForSystemPower(&notifierObject)
        }
        if let notifyPortRef = notifyPortRef {
            IONotificationPortDestroy(notifyPortRef)
        }
    }

    private func setupPowerEventHandling() {
        // Register for system power notifications
        rootPort = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &notifyPortRef,
            { (refCon, service, messageType, messageArgument) in
                guard let refCon = refCon else { return }
                let monitor = Unmanaged<PowerEventMonitor>.fromOpaque(refCon).takeUnretainedValue()
                monitor.handlePowerEvent(messageType: messageType, messageArgument: messageArgument)
            },
            &notifierObject
        )

        if rootPort != 0, let notifyPortRef = notifyPortRef {
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                IONotificationPortGetRunLoopSource(notifyPortRef).takeUnretainedValue(),
                .defaultMode
            )
        }

        // Display sleep/wake — these are the events that matter for monitor
        // use. NOTE: must use NSWorkspace's notificationCenter; the previous
        // implementation used NotificationCenter.default with the
        // "com.apple.screenIsLocked" name, which never fires there.
        let center = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.onPowerEvent?(.displayWillSleep, {})
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.onPowerEvent?(.displayDidWake, {})
        })
    }

    private func handlePowerEvent(messageType: UInt32, messageArgument: UnsafeMutableRawPointer?) {
        switch messageType {
        case UInt32(kIOMessageCanSystemSleep):
            // System asks permission to sleep — allow immediately.
            if rootPort != 0 {
                IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
            }

        case UInt32(kIOMessageSystemWillSleep):
            // DELAY the sleep until the handler is done (TV-off sent) or the
            // safety timeout fires. Previously IOAllowPowerChange was called
            // immediately, so the Mac slept before the network command
            // reached the TV.
            let port = rootPort
            let argument = Int(bitPattern: messageArgument)
            let allowed = ResumeGuard()
            let allowOnce = {
                DispatchQueue.main.async {
                    guard allowed.tryClaim() else { return }
                    if port != 0 {
                        IOAllowPowerChange(port, argument)
                    }
                }
            }

            // Safety net: never block sleep longer than maxSleepDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxSleepDelay) {
                allowOnce()
            }

            if let handler = onPowerEvent {
                handler(.systemWillSleep, allowOnce)
            } else {
                allowOnce()
            }

        case UInt32(kIOMessageSystemHasPoweredOn):
            onPowerEvent?(.systemDidWake, {})

        case UInt32(kIOMessageSystemWillPowerOff):
            onPowerEvent?(.systemWillShutdown, {})

        case UInt32(kIOMessageSystemWillRestart):
            onPowerEvent?(.systemWillRestart, {})

        default:
            break
        }
    }
}

// MARK: - User Idle Monitor

class UserIdleMonitor {
    private var timer: Timer?
    private var idleThreshold: TimeInterval
    private var isIdle = false

    /// Bundle IDs whose display-sleep assertions count as user activity.
    /// While one of these apps is playing video (holding the assertion), the
    /// user is never reported as idle, even with no keyboard/mouse input.
    var allowedAssertionBundleIDs: Set<String> = []

    var onIdleStateChanged: ((Bool) -> Void)?

    init(idleThreshold: TimeInterval = 300) { // 5 minutes default
        self.idleThreshold = idleThreshold
    }

    deinit {
        timer?.invalidate()
    }

    func startMonitoring() {
        scheduleNextCheck(in: 1.0)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func updateIdleThreshold(_ threshold: TimeInterval) {
        idleThreshold = threshold
    }

    /// Adaptive polling: instead of querying the IOKit registry every second,
    /// check roughly when the threshold could next be crossed.
    private func scheduleNextCheck(in interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.checkIdleState()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func checkIdleState() {
        let idleTime = getSystemIdleTime()
        var shouldBeIdle = idleTime >= idleThreshold

        // A whitelisted app holding an active display-sleep assertion (e.g. a
        // browser playing YouTube) counts as activity — don't turn the TV off
        // underneath an ongoing video just because mouse/keyboard are still.
        if shouldBeIdle && !allowedAssertionBundleIDs.isEmpty {
            let asserting = DisplaySleepAssertions.assertingBundleIDs()
            if !asserting.isDisjoint(with: allowedAssertionBundleIDs) {
                shouldBeIdle = false
            }
        }

        if shouldBeIdle != isIdle {
            isIdle = shouldBeIdle
            onIdleStateChanged?(isIdle)
        }

        // While active and far from the threshold, sleep most of the gap;
        // near the threshold (or while idle, waiting for activity) poll fast.
        let remaining = idleThreshold - idleTime
        let next = isIdle ? 1.0 : max(1.0, min(remaining * 0.5, 30.0))
        scheduleNextCheck(in: next)
    }

    private func getSystemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0
        defer {
            if iterator != 0 {
                IOObjectRelease(iterator)
            }
        }

        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        ) == KERN_SUCCESS else {
            return 0
        }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else {
            return 0
        }
        defer {
            IOObjectRelease(entry)
        }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry,
            &properties,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any],
              let hidIdleTime = dict["HIDIdleTime"] as? Int64 else {
            return 0
        }

        // Convert from nanoseconds to seconds
        return TimeInterval(hidIdleTime) / TimeInterval(NSEC_PER_SEC)
    }
}

// MARK: - Display Configuration Monitor

class DisplayConfigurationMonitor {
    var onDisplayConfigurationChanged: (() -> Void)?

    private var registered = false

    init() {
        setupDisplayMonitoring()
    }

    private func setupDisplayMonitoring() {
        let result = CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        registered = (result == .success)
    }

    deinit {
        if registered {
            CGDisplayRemoveReconfigurationCallback(
                displayReconfigurationCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    func getActiveDisplayCount() -> UInt32 {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        return displayCount
    }
}

/// Top-level C-compatible callback (a stored closure variable could be
/// deallocated/replaced and cause the remove call to mismatch the register
/// call — the original race noted in TODO.md).
private func displayReconfigurationCallback(
    display: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo = userInfo else { return }
    let monitor = Unmanaged<DisplayConfigurationMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if flags.contains(.addFlag) || flags.contains(.removeFlag) {
        DispatchQueue.main.async {
            monitor.onDisplayConfigurationChanged?()
        }
    }
}
