import XCTest
@testable import LGTVCompanionShared

/// Stand-in for a TV connection. connect() and register() take a moment, so
/// concurrent callers really overlap.
private final class FakeTransport: TVTransport {
    private let lock = NSLock()
    private var state = TVLinkState(isConnected: false, isPaired: false)
    private var connectCalls = 0
    private var registerCalls = 0
    private var failingConnects = 0

    var connects: Int { lock.withLock { connectCalls } }
    var registers: Int { lock.withLock { registerCalls } }

    /// The next `count` connect() calls throw.
    func failNextConnects(_ count: Int) {
        lock.withLock { failingConnects = count }
    }

    func linkState() async -> TVLinkState { lock.withLock { state } }

    func connect() async throws {
        let shouldFail: Bool = lock.withLock {
            connectCalls += 1
            if failingConnects > 0 { failingConnects -= 1; return true }
            return false
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        if shouldFail { throw WebOSError.timeout }
        lock.withLock { state.isConnected = true }
    }

    func register() async throws {
        lock.withLock { registerCalls += 1 }
        try await Task.sleep(nanoseconds: 50_000_000)
        lock.withLock { state.isPaired = true }
    }

    func disconnectAndWait() async {
        lock.withLock { state = TVLinkState(isConnected: false, isPaired: false) }
    }
}

final class TVSessionTests: XCTestCase {

    func testConcurrentCallersShareOneConnectAndOneRegister() async throws {
        let transport = FakeTransport()
        let session = TVSession(transport: transport)

        async let first: Void = session.ensureReady()
        async let second: Void = session.ensureReady()
        _ = try await (first, second)

        XCTAssertEqual(transport.connects, 1)
        XCTAssertEqual(transport.registers, 1)
    }

    func testReadyTransportIsLeftAlone() async throws {
        let transport = FakeTransport()
        let session = TVSession(transport: transport)
        try await session.ensureReady()

        try await session.ensureReady()

        XCTAssertEqual(transport.connects, 1)
        XCTAssertEqual(transport.registers, 1)
    }

    func testFailingConnectReachesBothCallersAndTheNextCallRetries() async throws {
        let transport = FakeTransport()
        transport.failNextConnects(1)
        let session = TVSession(transport: transport)

        let first = Task { try await session.ensureReady() }
        let second = Task { try await session.ensureReady() }
        let firstResult = await first.result
        let secondResult = await second.result

        XCTAssertThrowsError(try firstResult.get())
        XCTAssertThrowsError(try secondResult.get())
        XCTAssertEqual(transport.connects, 1, "both callers must share the failed attempt")
        XCTAssertEqual(transport.registers, 0)

        try await session.ensureReady()

        XCTAssertEqual(transport.connects, 2)
        XCTAssertEqual(transport.registers, 1)
    }

    func testReconnectBuildsAFreshConnection() async throws {
        let transport = FakeTransport()
        let session = TVSession(transport: transport)
        try await session.ensureReady()

        try await session.reconnect()

        XCTAssertEqual(transport.connects, 2)
        XCTAssertEqual(transport.registers, 2)
    }

    func testOnlyTransientErrorsAreRetried() {
        XCTAssertTrue(TVSession.isTransient(WebOSError.notConnected))
        XCTAssertTrue(TVSession.isTransient(WebOSError.timeout))
        XCTAssertTrue(TVSession.isTransient(WebOSError.networkError(URLError(.networkConnectionLost))))

        XCTAssertFalse(TVSession.isTransient(WebOSError.commandFailed("401 insufficient permissions")))
        XCTAssertFalse(TVSession.isTransient(WebOSError.pairingRejected))
        XCTAssertFalse(TVSession.isTransient(WebOSError.pairingRequired))
        XCTAssertFalse(TVSession.isTransient(WebOSError.invalidResponse))
        XCTAssertFalse(TVSession.isTransient(CancellationError()))
    }
}
