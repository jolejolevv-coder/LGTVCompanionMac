//
//  LGDisplayDetector.swift
//  LGTV Companion Shared
//
//  Answers "does the Mac currently output to an LG TV?" from the displays
//  macOS knows about. Used to gate every automatic power-off.
//

import AppKit
import CoreGraphics

public enum LGDisplayDetector {

    /// EDID manufacturer id "GSM" (LG Electronics) as CoreGraphics reports it.
    public static let lgVendorNumber: UInt32 = 0x1E6D
    /// LG TVs name themselves "LG TV SSCR2" and similar in their EDID.
    public static let lgTVNameMarker = "LG TV"
    /// Upper bound for the display list; a Mac never drives more.
    private static let maxDisplays: UInt32 = 16

    /// Pure matching rule, testable without hardware.
    public static func isLGTV(vendorNumber: UInt32, name: String?) -> Bool {
        if vendorNumber == lgVendorNumber { return true }
        guard let name else { return false }
        return name.localizedCaseInsensitiveContains(lgTVNameMarker)
    }

    /// Whether any online display (active, mirrored or asleep) is an LG TV.
    /// Online instead of active, so a display that is just going to sleep
    /// still counts. A pulled HDMI cable takes the display offline.
    @MainActor
    public static func macDrivesLGTV() -> Bool {
        let displays = onlineDisplays()
        let match = displays.first { isLGTV(vendorNumber: CGDisplayVendorNumber($0), name: screenName(for: $0)) }
        if let match {
            Log.tv.info("Auto off check: Mac drives LG TV display \(match, privacy: .public)")
        } else {
            Log.tv.info("Auto off check: no LG TV among \(displays.count, privacy: .public) displays, skipping power off")
        }
        return match != nil
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(maxDisplays, &ids, &count) == .success else {
            Log.tv.error("Auto off check: CGGetOnlineDisplayList failed")
            return []
        }
        return Array(ids.prefix(Int(count)))
    }

    /// The display's name, if it is currently a screen (asleep ones are not).
    @MainActor
    private static func screenName(for id: CGDirectDisplayID) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id
        }?.localizedName
    }
}
