//
//  DisplaySleepAssertions.swift
//  LGTV Companion Shared
//
//  Reads the macOS power-assertion registry to find apps that are keeping
//  the display awake — typically a browser or player during video playback.
//  This is the same mechanism that stops the Mac's own screen from sleeping,
//  so respecting it keeps the TV consistent with the Mac.
//

import Foundation
import AppKit
import IOKit
import IOKit.pwr_mgt

/// An app that is currently holding a display-sleep power assertion, i.e.
/// actively keeping the screen on (usually while playing video).
public struct AssertingApp: Identifiable, Hashable {
    public let bundleID: String
    public let name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public enum DisplaySleepAssertions {
    /// Assertion types that keep the *display* awake. A video player holds one
    /// of these only while content is actually playing — not just while the
    /// app is open. System-sleep-only assertions are deliberately ignored.
    private static let displayAssertionTypes: Set<String> = [
        kIOPMAssertionTypePreventUserIdleDisplaySleep as String, // "PreventUserIdleDisplaySleep"
        kIOPMAssertionTypeNoDisplaySleep as String               // legacy "NoDisplaySleepAssertion"
    ]

    /// Bundle IDs of apps currently holding an active display-sleep assertion.
    public static func assertingBundleIDs() -> Set<String> {
        Set(currentAssertingApps().map { $0.bundleID })
    }

    /// All apps currently holding an active display-sleep assertion,
    /// deduplicated by bundle ID. Reads the live IOKit registry — no special
    /// permission required.
    public static func currentAssertingApps() -> [AssertingApp] {
        var assertionsByPID: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertionsByPID) == kIOReturnSuccess,
              let dict = assertionsByPID?.takeRetainedValue()
                  as? [NSNumber: [[String: Any]]] else {
            return []
        }

        var seen = Set<String>()
        var result: [AssertingApp] = []

        for (pidNumber, assertions) in dict {
            guard holdsActiveDisplayAssertion(assertions) else { continue }

            let pid = pid_t(truncating: pidNumber)
            guard let app = appInfo(for: pid) else { continue }
            guard seen.insert(app.bundleID).inserted else { continue }
            result.append(app)
        }

        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// True if any of the process's assertions is a display-sleep assertion
    /// that is currently switched on. Some apps keep assertion objects around
    /// at level "off" — those must not count.
    private static func holdsActiveDisplayAssertion(_ assertions: [[String: Any]]) -> Bool {
        assertions.contains { assertion in
            guard let type = assertion[kIOPMAssertionTypeKey as String] as? String,
                  displayAssertionTypes.contains(type) else {
                return false
            }
            if let level = assertion[kIOPMAssertionLevelKey as String] as? Int {
                return level == Int(kIOPMAssertionLevelOn)
            }
            return true
        }
    }

    private static func appInfo(for pid: pid_t) -> AssertingApp? {
        guard let running = NSRunningApplication(processIdentifier: pid),
              let bundleID = running.bundleIdentifier else {
            return nil
        }
        let name = running.localizedName ?? bundleID
        return AssertingApp(bundleID: bundleID, name: name)
    }
}
