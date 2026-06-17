//
//  DisplayControl.swift
//  LGTV Companion Shared
//
//  Resolution / HiDPI scaling control for connected displays
//  (Windows-style "100% / 150% / 200%" scale options).
//

import Foundation
import AppKit
import CoreGraphics

public struct DisplayInfo: Identifiable, Equatable {
    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltin: Bool
}

public struct DisplayModeInfo: Identifiable, Equatable {
    public let cgMode: CGDisplayMode
    public let width: Int          // logical (points)
    public let height: Int
    public let pixelWidth: Int     // physical pixels
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isHiDPI: Bool
    /// Windows-style scale relative to the panel's native pixels:
    /// native pixels rendered 1:1 = 100%, half logical size = 200%, etc.
    public var scalePercent: Int = 100

    public var id: String { "\(width)x\(height)@\(Int(refreshRate))\(isHiDPI ? "HiDPI" : "")" }

    public var label: String {
        var parts = ["\(width) × \(height)"]
        parts.append("(\(scalePercent)%)")
        if refreshRate > 0 { parts.append("\(Int(refreshRate.rounded())) Hz") }
        if isHiDPI { parts.append("HiDPI") }
        return parts.joined(separator: "  ")
    }

    public static func == (lhs: DisplayModeInfo, rhs: DisplayModeInfo) -> Bool {
        lhs.id == rhs.id
    }
}

public enum DisplayControl {

    /// All active displays. TVs show up as external displays.
    public static func activeDisplays(includeBuiltin: Bool = false) -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        return ids.compactMap { id in
            let builtin = CGDisplayIsBuiltin(id) != 0
            if builtin && !includeBuiltin { return nil }
            return DisplayInfo(id: id, name: displayName(for: id), isBuiltin: builtin)
        }
    }

    /// Scaled resolution options for a display, sorted large → small.
    /// Includes HiDPI ("Retina") modes — these are the Windows-style
    /// scaling steps — plus the native 100% mode.
    public static func scalingModes(for display: CGDirectDisplayID) -> [DisplayModeInfo] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let cgModes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] else {
            return []
        }

        let usable = cgModes.filter { $0.isUsableForDesktopGUI() }
        guard !usable.isEmpty else { return [] }

        let panelWidth = Self.panelWidth(of: usable)

        var infos: [DisplayModeInfo] = usable.map { Self.makeInfo($0, panelWidth: panelWidth) }

        // Dedupe by logical size: prefer HiDPI, then highest refresh.
        var best: [String: DisplayModeInfo] = [:]
        for info in infos {
            let key = "\(info.width)x\(info.height)"
            if let existing = best[key] {
                let better = (info.isHiDPI && !existing.isHiDPI)
                    || (info.isHiDPI == existing.isHiDPI && info.refreshRate > existing.refreshRate)
                if better { best[key] = info }
            } else {
                best[key] = info
            }
        }
        infos = Array(best.values)

        // Keep the menu tidy: the native 100% mode plus Windows-style
        // scale steps. (Tools like BetterDisplay inject dozens of
        // intermediate modes — without this filter the menu is unusable.)
        let commonSteps = [100, 125, 150, 175, 200, 250, 300]
        infos = infos.filter { info in
            info.width == panelWidth
                || (info.isHiDPI && commonSteps.contains { abs($0 - info.scalePercent) <= 2 })
        }

        return infos.sorted { $0.width > $1.width }
    }

    /// True panel resolution = widest mode that maps 1:1 (points == pixels).
    /// Don't trust max pixelWidth: virtual-display tools (BetterDisplay)
    /// expose supersampled framebuffers larger than the panel.
    private static func panelWidth(of modes: [CGDisplayMode]) -> Int {
        let oneToOne = modes.filter { $0.pixelWidth == $0.width }
        return oneToOne.map(\.width).max()
            ?? modes.map(\.pixelWidth).max()
            ?? 0
    }

    private static func makeInfo(_ mode: CGDisplayMode, panelWidth: Int) -> DisplayModeInfo {
        var info = DisplayModeInfo(
            cgMode: mode,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate,
            isHiDPI: mode.pixelWidth > mode.width
        )
        if info.width > 0, panelWidth > 0 {
            info.scalePercent = Int((Double(panelWidth) / Double(info.width) * 100).rounded())
        }
        return info
    }

    public static func currentMode(for display: CGDirectDisplayID) -> DisplayModeInfo? {
        guard let mode = CGDisplayCopyDisplayMode(display) else { return nil }
        let all = scalingModes(for: display)
        if let match = all.first(where: {
            $0.cgMode.width == mode.width && $0.cgMode.height == mode.height
                && $0.cgMode.pixelWidth == mode.pixelWidth
        }) ?? all.first(where: { $0.width == mode.width && $0.height == mode.height }) {
            return match
        }
        // Current mode not in our filtered list (e.g. an exotic
        // BetterDisplay step) — synthesize an entry so the UI shows it.
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let allModes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? [mode]
        return makeInfo(mode, panelWidth: panelWidth(of: allModes))
    }

    /// Switches the display to the given mode (persists across reboots).
    @discardableResult
    public static func setMode(_ info: DisplayModeInfo, on display: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config = config else {
            return false
        }
        guard CGConfigureDisplayWithDisplayMode(config, display, info.cgMode, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    private static func displayName(for id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               CGDirectDisplayID(num.uint32Value) == id {
                return screen.localizedName
            }
        }
        return "Display \(id)"
    }
}
