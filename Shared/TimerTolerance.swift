//
//  TimerTolerance.swift
//  LGTV Companion Shared
//
//  Lets macOS coalesce the app's timers with other wake-ups.
//

import Foundation

public enum TimerTolerance {
    /// Share of the interval a timer may fire late. 10 % is invisible for
    /// the app's polling timers and saves wake-ups.
    public static let fractionOfInterval: TimeInterval = 0.1

    public static func tolerance(for interval: TimeInterval) -> TimeInterval {
        interval * fractionOfInterval
    }
}
