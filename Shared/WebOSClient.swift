//
//  WebOSClient.swift
//  LGTV Companion Shared
//
//  Handles WebSocket communication with LG WebOS TVs
//

import Foundation
import Network

public enum WebOSError: Error, LocalizedError {
    case notConnected
    case invalidResponse
    case pairingRequired
    case pairingRejected
    case commandFailed(String)
    case networkError(Error)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to TV"
        case .invalidResponse: return "Invalid response from TV"
        case .pairingRequired: return "Pairing required"
        case .pairingRejected: return "Pairing rejected on TV"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .timeout: return "Request timed out"
        }
    }
}

public struct WebOSDevice: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var ipAddress: String
    public var macAddress: String
    public var pairingKey: String?
    public var autoManage: Bool
    public var enabled: Bool
    /// Use screen-off (instant on/off, no reboot) instead of full power-off.
    /// Recommended when the TV is used as a monitor.
    public var useScreenOff: Bool
    /// WebOS foreground-app id of the input the Mac is connected to
    /// (e.g. "com.webos.app.hdmi3"). When set, automatic power-off is skipped
    /// while the TV is showing a *different* input (e.g. a PS5 on another HDMI).
    /// nil = not configured → automatic power-off behaves as before.
    public var macInputAppId: String?

    public init(id: UUID = UUID(), name: String, ipAddress: String, macAddress: String,
         pairingKey: String? = nil, autoManage: Bool = true, enabled: Bool = true,
         useScreenOff: Bool = true, macInputAppId: String? = nil) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.pairingKey = pairingKey
        self.autoManage = autoManage
        self.enabled = enabled
        self.useScreenOff = useScreenOff
        self.macInputAppId = macInputAppId
    }

    // Backwards-compatible decoding (older saved devices lack useScreenOff)
    enum CodingKeys: String, CodingKey {
        case id, name, ipAddress, macAddress, pairingKey, autoManage, enabled, useScreenOff, macInputAppId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        ipAddress = try c.decode(String.self, forKey: .ipAddress)
        macAddress = try c.decode(String.self, forKey: .macAddress)
        pairingKey = try c.decodeIfPresent(String.self, forKey: .pairingKey)
        autoManage = try c.decodeIfPresent(Bool.self, forKey: .autoManage) ?? true
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        useScreenOff = try c.decodeIfPresent(Bool.self, forKey: .useScreenOff) ?? true
        macInputAppId = try c.decodeIfPresent(String.self, forKey: .macInputAppId)
    }
}

/// One-shot flag, safe for use from multiple closures on the same queue.
final class ResumeGuard {
    private var claimed = false
    private let lock = NSLock()

    /// Returns true exactly once.
    func tryClaim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

public class WebOSClient: ObservableObject {
    @Published public var isConnected = false
    @Published public var isPaired = false

    /// Called when the TV hands out a (new) client key, so the owner can persist it.
    public var onPairingKeyUpdated: ((UUID, String) -> Void)?

    private var connection: NWConnection?
    public private(set) var device: WebOSDevice
    private var messageId = 1
    private var pendingRequests: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var pairingContinuation: CheckedContinuation<Void, Error>?
    /// Monotonic token identifying the current pairing attempt. A scheduled
    /// pairing-timeout only fires for the attempt it was created for — this
    /// stops a stale timer from a previous register() resuming a later one.
    private var pairingAttemptID = 0

    /// Serial queue: all connection callbacks and shared state live here.
    private let queue = DispatchQueue(label: "com.lgtvcompanion.webosclient")

    private static let requestTimeout: TimeInterval = 10
    private static let pairingTimeout: TimeInterval = 60 // user must accept prompt on TV

    public init(device: WebOSDevice) {
        self.device = device
    }

    deinit {
        connection?.cancel()
    }

    // MARK: - Connection Management

    /// Connects via secure WebSocket (wss://:3001) first — required on newer
    /// webOS firmware — and falls back to plain ws://:3000 for older TVs.
    public func connect() async throws {
        do {
            try await connect(secure: true)
        } catch {
            try await connect(secure: false)
        }
    }

    private func connect(secure: Bool) async throws {
        let portNumber: UInt16 = secure ? 3001 : 3000

        let parameters: NWParameters
        if secure {
            // LG TVs use a self-signed certificate — accept it.
            // NWParameters(tls:) + NWConnection(host:port:using:) is used instead of
            // NWConnection(to: .url("wss://..."), using:) because combining a wss:// URL
            // with explicit TLS parameters causes a conflict in Network.framework that
            // prevents the TLS handshake from completing.
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(
                tlsOptions.securityProtocolOptions,
                { _, _, complete in complete(true) },
                queue
            )
            parameters = NWParameters(tls: tlsOptions)
        } else {
            parameters = .tcp
        }
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        guard let nwPort = NWEndpoint.Port(rawValue: portNumber) else {
            throw WebOSError.networkError(NSError(domain: "InvalidPort", code: -1))
        }
        let newConnection = NWConnection(
            host: NWEndpoint.Host(device.ipAddress),
            port: nwPort,
            using: parameters
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Guard against double resume (.ready followed by .failed, etc.)
            // Reference type instead of captured var — avoids concurrency
            // warnings; all access happens on the serial `queue`.
            let resumed = ResumeGuard()

            newConnection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                // The state handler runs on `queue`. When connect() falls back
                // from secure(3001) to insecure(3000) the old connection lives
                // on and may later emit .failed/.cancelled — ignore those so a
                // dead connection can't fail the pending requests of the live
                // one. .ready is exempt: it is what installs the connection.
                switch state {
                case .ready:
                    DispatchQueue.main.async { self.isConnected = true }
                    self.startReceiving(on: newConnection)
                    if resumed.tryClaim() { continuation.resume() }
                case .failed(let error):
                    if self.connection === newConnection {
                        DispatchQueue.main.async { self.isConnected = false }
                        self.failAllPending(with: .networkError(error))
                    }
                    if resumed.tryClaim() { continuation.resume(throwing: WebOSError.networkError(error)) }
                case .cancelled:
                    if self.connection === newConnection {
                        DispatchQueue.main.async { self.isConnected = false }
                        self.failAllPending(with: .notConnected)
                    }
                    if resumed.tryClaim() { continuation.resume(throwing: WebOSError.notConnected) }
                default:
                    break
                }
            }

            // Connection-level timeout
            queue.asyncAfter(deadline: .now() + Self.requestTimeout) {
                if resumed.tryClaim() {
                    newConnection.cancel()
                    continuation.resume(throwing: WebOSError.timeout)
                }
            }

            // Install + start on `queue` so every read/write of `connection`
            // happens on the one serial queue. Because disconnect() also tears
            // down on `queue`, a disconnect() immediately followed by connect()
            // (the reconnect-after-error path) is ordered correctly: the
            // teardown is enqueued first and runs before this assignment.
            self.queue.async {
                self.connection = newConnection
                newConnection.start(queue: self.queue)
            }
        }
    }

    public func disconnect() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.connection?.cancel()
            self.connection = nil
            self.failAllPending(with: .notConnected)
        }
        DispatchQueue.main.async {
            self.isConnected = false
            self.isPaired = false
        }
    }

    /// Like `disconnect()`, but completes only after the teardown has actually
    /// run on `queue`. The reconnect path must await this before connect(),
    /// otherwise the fire-and-forget teardown can cancel the new connection.
    public func disconnectAndWait() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                self?.connection?.cancel()
                self?.connection = nil
                self?.failAllPending(with: .notConnected)
                cont.resume()
            }
        }
        await MainActor.run {
            self.isConnected = false
            self.isPaired = false
        }
    }

    // MARK: - Pairing

    /// Registers with the TV. Completes only after the TV sends "registered"
    /// (i.e. after the user accepted the pairing prompt, if needed).
    public func register() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                // Build the message on `queue`: reading device.pairingKey here
                // (rather than off-queue) keeps all access to `device` on the
                // one serial queue, where handleReceivedData also writes it.
                let pairingMessage: [String: Any] = [
                    "type": "register",
                    "id": "register_0",
                    "payload": [
                        "forcePairing": false,
                        "pairingType": "PROMPT",
                        "client-key": self.device.pairingKey ?? "",
                        "manifest": Self.manifest
                    ]
                ]

                self.pairingContinuation = continuation
                self.pairingAttemptID &+= 1
                let attempt = self.pairingAttemptID

                // Pairing timeout (user has to walk to the TV). Tagged with the
                // attempt id so a stale timer from an earlier register() cannot
                // resume a later attempt's continuation.
                self.queue.asyncAfter(deadline: .now() + Self.pairingTimeout) {
                    guard attempt == self.pairingAttemptID,
                          let cont = self.pairingContinuation else { return }
                    self.pairingContinuation = nil
                    cont.resume(throwing: WebOSError.timeout)
                }

                do {
                    try self.sendRaw(pairingMessage)
                } catch {
                    guard attempt == self.pairingAttemptID,
                          let cont = self.pairingContinuation else { return }
                    self.pairingContinuation = nil
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Commands

    /// Full power off (TV reboots on next power-on).
    public func powerOff() async throws {
        _ = try await request(uri: "ssap://system/turnOff")
    }

    /// Screen off only — TV stays on, picture returns instantly.
    /// Ideal for monitor use: no boot time, no HDMI re-handshake.
    /// webOS 5+ uses "tvpower", webOS 4.x uses "tv.power" — try both.
    public func screenOff() async throws {
        do {
            _ = try await request(uri: "ssap://com.webos.service.tvpower/power/turnOffScreen",
                                  payload: ["standbyMode": "active"])
        } catch WebOSError.commandFailed {
            _ = try await request(uri: "ssap://com.webos.service.tv.power/power/turnOffScreen",
                                  payload: ["standbyMode": "active"])
        }
    }

    /// Turn the screen back on after screenOff().
    public func screenOn() async throws {
        do {
            _ = try await request(uri: "ssap://com.webos.service.tvpower/power/turnOnScreen",
                                  payload: ["standbyMode": "active"])
        } catch WebOSError.commandFailed {
            _ = try await request(uri: "ssap://com.webos.service.tv.power/power/turnOnScreen",
                                  payload: ["standbyMode": "active"])
        }
    }

    /// Current power state, e.g. "Active", "Active Standby", "Screen Off".
    public func getPowerState() async throws -> String {
        let response = try await request(uri: "ssap://com.webos.service.tvpower/power/getPowerState")
        let payload = response["payload"] as? [String: Any]
        return payload?["state"] as? String ?? "Unknown"
    }

    public func getDeviceInfo() async throws -> [String: Any] {
        try await request(uri: "ssap://system/getSystemInfo")
    }

    /// The app id currently in the foreground. For external sources this is an
    /// input id like "com.webos.app.hdmi3"; for TV apps the app's bundle id.
    /// Returns nil if the TV doesn't report one.
    public func getForegroundAppInfo() async throws -> String? {
        let response = try await request(
            uri: "ssap://com.webos.applicationManager/getForegroundAppInfo")
        let payload = response["payload"] as? [String: Any]
        return payload?["appId"] as? String
    }

    /// Current volume + mute state. Handles both webOS payload shapes
    /// (flat on older firmware, nested "volumeStatus" on webOS 5+).
    public func getAudioStatus() async throws -> (volume: Int?, muted: Bool?) {
        let response = try await request(uri: "ssap://audio/getVolume")
        let payload = response["payload"] as? [String: Any]
        if let vs = payload?["volumeStatus"] as? [String: Any] {
            return (vs["volume"] as? Int, vs["muteStatus"] as? Bool)
        }
        return (payload?["volume"] as? Int, payload?["muted"] as? Bool)
    }

    public func setVolume(_ volume: Int) async throws {
        _ = try await request(uri: "ssap://audio/setVolume", payload: ["volume": volume])
    }

    public func volumeUp() async throws {
        _ = try await request(uri: "ssap://audio/volumeUp")
    }

    public func volumeDown() async throws {
        _ = try await request(uri: "ssap://audio/volumeDown")
    }

    public func setMute(_ muted: Bool) async throws {
        _ = try await request(uri: "ssap://audio/setMute", payload: ["mute": muted])
    }

    public func switchInput(_ inputId: String) async throws {
        _ = try await request(uri: "ssap://tv/switchInput", payload: ["inputId": inputId])
    }

    // MARK: - Private Helpers

    private static let manifest: [String: Any] = [
        "manifestVersion": 1,
        "appVersion": "1.0",
        "signed": [
            "created": "20250101",
            "appId": "com.lgtvcompanion.mac",
            "vendorId": "com.lgtvcompanion",
            "localizedAppNames": ["": "LGTV Companion", "de-DE": "LGTV Companion"],
            "localizedVendorNames": ["": "LGTV Companion"],
            "permissions": [
                "TEST_SECURE", "CONTROL_INPUT_TEXT", "CONTROL_MOUSE_AND_KEYBOARD",
                "READ_INSTALLED_APPS", "READ_LGE_SDX", "READ_NOTIFICATIONS", "SEARCH",
                "WRITE_SETTINGS", "WRITE_NOTIFICATION_ALERT", "CONTROL_POWER",
                "READ_CURRENT_CHANNEL", "READ_RUNNING_APPS", "READ_UPDATE_INFO",
                "UPDATE_FROM_REMOTE_APP", "READ_LGE_TV_INPUT_EVENTS", "READ_TV_CURRENT_TIME"
            ],
            "serial": "2f930e2d2cfe083771f68e4fe7bb07"
        ],
        "permissions": [
            "LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CLOSE", "TEST_OPEN",
            "TEST_PROTECTED", "CONTROL_AUDIO", "CONTROL_DISPLAY",
            "CONTROL_INPUT_JOYSTICK", "CONTROL_INPUT_MEDIA_RECORDING",
            "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_TV", "CONTROL_POWER",
            "READ_APP_STATUS", "READ_CURRENT_CHANNEL", "READ_INPUT_DEVICE_LIST",
            "READ_NETWORK_STATE", "READ_RUNNING_APPS", "READ_TV_CHANNEL_LIST",
            "WRITE_NOTIFICATION_TOAST", "READ_POWER_STATE", "READ_COUNTRY_INFO",
            // Required for turnOffScreen/turnOnScreen and tvpower APIs —
            // without these the TV answers "401 insufficient permissions".
            "CONTROL_TV_SCREEN", "CONTROL_TV_POWER", "CONTROL_TV_STANBY",
            "CONTROL_WOL", "READ_SETTINGS", "READ_TV_CURRENT_TIME"
        ],
        "signatures": [
            [
                "signatureVersion": 1,
                "signature": "eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRyaMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A8r6klyFDYcGUn9xQhXy/5EYhiVvBBLy+m0HIz4VQfDKOTmwVBq5BQYdDp6zZAq2B4VBKkzUYlFfBZ0TJBn4VBFhBkTQm5FBjFQkVTBFABxBFDhBFEBKQBKFQk5FgFZpQFAoFBJI4kQT4="
            ]
        ]
    ]

    private func request(uri: String, payload: [String: Any]? = nil) async throws -> [String: Any] {
        var message: [String: Any] = ["type": "request", "uri": uri]
        if let payload = payload {
            message["payload"] = payload
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let id = "request_\(self.messageId)"
                self.messageId += 1
                message["id"] = id

                // Store continuation BEFORE sending — the response can arrive
                // before the send completion fires.
                self.pendingRequests[id] = continuation

                // Per-request timeout so continuations never leak
                self.queue.asyncAfter(deadline: .now() + Self.requestTimeout) {
                    if let cont = self.pendingRequests.removeValue(forKey: id) {
                        cont.resume(throwing: WebOSError.timeout)
                    }
                }

                do {
                    try self.sendRaw(message)
                } catch {
                    if let cont = self.pendingRequests.removeValue(forKey: id) {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Must be called on `queue`.
    private func sendRaw(_ message: [String: Any]) throws {
        guard let connection = connection else {
            throw WebOSError.notConnected
        }

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])

        connection.send(content: jsonData, contentContext: context, isComplete: true,
                        completion: .contentProcessed { _ in })
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.handleReceivedData(data)
            }

            if error == nil {
                self.startReceiving(on: connection)
            } else {
                self.failAllPending(with: .notConnected)
            }
        }
    }

    /// Runs on `queue` (connection started there).
    private func handleReceivedData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let type = json["type"] as? String

        // Pairing flow
        if type == "registered" {
            if let payload = json["payload"] as? [String: Any],
               let clientKey = payload["client-key"] as? String {
                device.pairingKey = clientKey
                DispatchQueue.main.async { self.isPaired = true }
                onPairingKeyUpdated?(device.id, clientKey)
            }
            // Invalidate this attempt's pending timeout before resuming.
            pairingAttemptID &+= 1
            if let cont = pairingContinuation {
                pairingContinuation = nil
                cont.resume()
            }
            return
        }

        if let id = json["id"] as? String, id == "register_0" {
            if type == "error" {
                pairingAttemptID &+= 1
                if let cont = pairingContinuation {
                    pairingContinuation = nil
                    cont.resume(throwing: WebOSError.pairingRejected)
                }
            }
            // type == "response" with pairingType PROMPT: user must confirm
            // on the TV — keep waiting for "registered".
            return
        }

        // Regular responses
        guard let id = json["id"] as? String,
              let continuation = pendingRequests.removeValue(forKey: id) else {
            return
        }

        // webOS reports command-level failures two ways: a top-level
        // type:"error", OR a type:"response" whose payload carries
        // returnValue == false (e.g. "401 insufficient permissions", a
        // service that exists but rejects the call). Both must surface as
        // commandFailed so callers — notably the screenOff()/screenOn()
        // webOS5→webOS4 fallback — actually see the failure.
        let payload = json["payload"] as? [String: Any]
        if type == "error" {
            let errorText = json["error"] as? String
                ?? payload?["errorText"] as? String ?? "unknown error"
            continuation.resume(throwing: WebOSError.commandFailed(errorText))
        } else if let payload = payload, (payload["returnValue"] as? Bool) == false {
            let errorText = payload["errorText"] as? String ?? "returnValue=false"
            continuation.resume(throwing: WebOSError.commandFailed(errorText))
        } else {
            continuation.resume(returning: json)
        }
    }

    /// Must be called on `queue`.
    private func failAllPending(with error: WebOSError) {
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
        if let cont = pairingContinuation {
            pairingAttemptID &+= 1
            pairingContinuation = nil
            cont.resume(throwing: error)
        }
    }
}
