//
//  TVFailureText.swift
//  LGTV Companion Shared
//
//  Turns a failed TV command into one short sentence for the user: what
//  happened and what to do about it.
//

import Foundation

enum TVFailureText {

    /// "Unable to reach LG OLED. Check that the TV is on and on the same network."
    static func message(for error: Error, tvName: String) -> String {
        if let webOSError = error as? WebOSError {
            switch webOSError {
            case .notConnected, .timeout, .networkError:
                return "Unable to reach \(tvName). Check that the TV is on and on the same network."
            case .pairingRequired:
                return "\(tvName) is not paired yet. Open LGTV Companion and pair the TV."
            case .pairingRejected:
                return "\(tvName) rejected the pairing. Try again and accept the prompt on the TV."
            case .commandFailed(let reason):
                return "\(tvName) refused the command: \(reason)"
            case .invalidResponse:
                return "\(tvName) sent an unexpected answer. Try again."
            }
        }
        if let managerError = error as? DeviceManagerError {
            switch managerError {
            case .deviceDisabled:
                return "\(tvName) is disabled. Enable it in LGTV Companion first."
            case .deviceNotFound, .autoManageDisabled, .connectionFailed:
                return "Unable to reach \(tvName). Check that the TV is on and on the same network."
            }
        }
        return "\(tvName): \(error.localizedDescription)"
    }
}
