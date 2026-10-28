//
//  TVSession.swift
//  LGTV Companion Shared
//
//  Makes sure a TV connection is open and paired, once, no matter how many
//  commands ask for it at the same time.
//

import Foundation

/// What `TVSession` needs from a TV connection. `WebOSClient` is the real one;
/// tests use a fake so the connect/register races run without a TV.
protocol TVTransport: AnyObject {
    /// Current flags, read on the main actor (the client publishes them there).
    func linkState() async -> TVLinkState
    func connect() async throws
    func register() async throws
    func disconnectAndWait() async
}

struct TVLinkState: Equatable {
    var isConnected: Bool
    var isPaired: Bool
}

/// Owns the "ensure connected and paired" step of one TV. Callers that arrive
/// while it is running wait for the same attempt instead of starting a second
/// connect/register on the same socket (which would leave the first caller
/// hanging, see WebOSClient.register()).
actor TVSession {
    private let transport: TVTransport
    /// The attempt currently running. nil when nothing is in flight, so a
    /// failed attempt is retried by the next caller.
    private var inFlight: Task<Void, Error>?

    init(transport: TVTransport) {
        self.transport = transport
    }

    /// Returns once the transport is connected and paired. Every caller gets
    /// the result of the same attempt, including its error.
    func ensureReady() async throws {
        if let running = inFlight {
            return try await running.value
        }
        let transport = self.transport
        let attempt = Task {
            do {
                try await Self.connectAndPair(transport)
            } catch {
                await self.attemptFinished()
                throw error
            }
            await self.attemptFinished()
        }
        inFlight = attempt
        try await attempt.value
    }

    /// Cleared by the attempt itself, on the actor, so a caller can never
    /// join an attempt whose result is already stale.
    private func attemptFinished() {
        inFlight = nil
    }

    /// Drops a stale connection and builds a fresh one. Awaits the teardown
    /// first: a fire-and-forget disconnect runs on the client's queue and
    /// would otherwise race connect() and cancel the brand-new connection.
    func reconnect() async throws {
        await transport.disconnectAndWait()
        try await ensureReady()
    }

    private static func connectAndPair(_ transport: TVTransport) async throws {
        var state = await transport.linkState()
        var didConnect = false
        if !state.isConnected {
            try await transport.connect()
            didConnect = true
            state = await transport.linkState()
        }
        // A new socket always has to register, whatever the flag said.
        if didConnect || !state.isPaired {
            try await transport.register()
        }
    }
}
