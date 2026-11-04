//
//  AutoOffPolicy.swift
//  LGTV Companion Shared
//
//  Decides whether an automatic power-off (idle, sleep, shutdown, display
//  change) may turn a TV off. Manual power-off from the menu never asks.
//

import Foundation

/// What the TV reports as its current input, compared with the Mac's input.
public enum TVInputState: Equatable, Sendable {
    /// The TV shows the input the Mac is connected to.
    case mac
    /// The TV shows something else, for example a console on another port.
    case other
    /// The input could not be read (TV did not answer).
    case unknown
    /// No Mac input is configured for this TV.
    case notConfigured
}

public enum AutoOffPolicy {

    /// - Parameters:
    ///   - macDrivesLGTV: whether the Mac currently outputs to an LG TV display.
    ///   - input: what the TV shows right now.
    /// - Returns: true when the automatic power-off may turn this TV off.
    ///
    /// Without the Mac on the TV the answer is always no: the TV belongs to
    /// someone else then (cable unplugged, console playing). With the Mac on
    /// the TV, only a different input blocks it; an unreadable or missing
    /// input setting still allows it, so a flaky query never disables the
    /// core feature.
    public static func mayPowerOff(macDrivesLGTV: Bool, input: TVInputState) -> Bool {
        guard macDrivesLGTV else { return false }
        switch input {
        case .mac, .unknown, .notConfigured:
            return true
        case .other:
            return false
        }
    }
}
