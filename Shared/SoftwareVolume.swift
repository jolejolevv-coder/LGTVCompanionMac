//
//  SoftwareVolume.swift
//  LGTV Companion Shared
//
//  Pure volume math and mode selection for the Mac-side software volume.
//  No audio APIs in here, so it stays unit-testable.
//

import Foundation

public enum SoftwareVolume {
    /// Same number of key steps as the macOS volume keys.
    public static let stepCount = 16

    /// Level-to-gain curve exponent. Loudness perception is roughly
    /// logarithmic; a cubic curve makes the 16 steps sound evenly spaced,
    /// where a linear one would bunch all audible change at the bottom.
    public static let gainExponent: Double = 3

    public static func clamp(_ level: Double) -> Double {
        min(max(level, 0), 1)
    }

    /// Linear sample multiplier for a slider level in 0...1. Never above 1:
    /// amplifying would clip.
    public static func gain(forLevel level: Double, muted: Bool) -> Float {
        if muted { return 0 }
        return Float(pow(clamp(level), gainExponent))
    }

    /// Moves the level by `delta` key steps, snapped to the step grid.
    public static func stepped(_ level: Double, by delta: Int) -> Double {
        let steps = Double(stepCount)
        let current = (clamp(level) * steps).rounded()
        return clamp((current + Double(delta)) / steps)
    }

    /// Software volume takes over only when the TV says it cannot change the
    /// volume itself (fixed-level output such as optical) AND the Mac's sound
    /// actually goes out to a display. An unknown TV answer (nil) keeps the
    /// old behavior of sending the keys to the TV.
    public static func shouldControl(enabled: Bool,
                                     tvCanAdjustVolume: Bool?,
                                     outputIsDigitalDisplay: Bool) -> Bool {
        enabled && tvCanAdjustVolume == false && outputIsDigitalDisplay
    }
}
