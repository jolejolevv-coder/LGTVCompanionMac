//
//  VolumeKeyRoute.swift
//  LGTV Companion Shared
//
//  Decides where a volume key press goes. Pure, so every combination of
//  speaker, TV and software volume state can be tested without hardware.
//

import Foundation

/// Where one volume key press is sent.
public enum VolumeKeyRoute: Equatable, Sendable {
    /// The Edifier speakers, over Bluetooth.
    case speakers
    /// The Mac's own sound, damped through the Core Audio tap.
    case softwareVolume
    /// The first enabled TV.
    case tv
    /// Nobody handles it. The key is not swallowed and macOS keeps control.
    case passThrough

    /// Picks the route, in this order:
    /// 1. Speakers, when they can handle volume keys. Real speaker control
    ///    beats everything else.
    /// 2. Pass through, when no TV is enabled.
    /// 3. Software volume, when it is active.
    /// 4. Pass through, when the TV says it cannot change the volume and the
    ///    Mac's sound does not go to a display (headphones, built-in speakers).
    /// 5. The TV. This includes an unknown TV answer (`tvCanAdjustVolume` is
    ///    nil), which keeps the old behavior of sending the keys to the TV.
    ///
    /// Every key takes the same route, mute included, so mute can never reach
    /// the TV while the speakers or the software volume own the volume.
    static func route(speakersCanHandleVolumeKeys: Bool,
                      hasEnabledTV: Bool,
                      softwareVolumeActive: Bool,
                      tvCanAdjustVolume: Bool?) -> VolumeKeyRoute {
        if speakersCanHandleVolumeKeys { return .speakers }
        guard hasEnabledTV else { return .passThrough }
        if softwareVolumeActive { return .softwareVolume }
        if tvCanAdjustVolume == false { return .passThrough }
        return .tv
    }
}
