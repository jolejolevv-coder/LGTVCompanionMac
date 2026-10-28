//
//  MainThread.swift
//  LGTV Companion Shared
//
//  Hands work from a background queue to the main actor.
//

import Foundation

/// The one place where a callback that runs on some other queue gets back to
/// the main actor. `DispatchQueue.main.async` keeps the order of calls (a
/// `Task { @MainActor in }` does not promise it), and the main queue is the
/// main actor's executor, so `assumeIsolated` never traps here.
public enum MainThread {
    /// Runs `body` on the main queue, as soon as the queue gets to it.
    public static func async(_ body: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated(body)
        }
    }

    /// Runs `body` on the main queue after `seconds`.
    public static func asyncAfter(seconds: TimeInterval,
                                  _ body: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated(body)
        }
    }
}
