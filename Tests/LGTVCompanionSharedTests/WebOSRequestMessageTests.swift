import XCTest
@testable import LGTVCompanionShared

final class WebOSRequestMessageTests: XCTestCase {

    /// Encodes and decodes like sendRaw does, so the test sees what the TV sees.
    private func wireObject(_ message: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: message)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Register

    func testRegisterMessageEnvelope() throws {
        let wire = try wireObject(WebOSClient.registerMessage(clientKey: "abc123"))
        XCTAssertEqual(wire["type"] as? String, "register")
        XCTAssertEqual(wire["id"] as? String, "register_0", "the client waits for this id")
        XCTAssertEqual(Set(wire.keys), ["type", "id", "payload"])
    }

    func testRegisterPayload() throws {
        let wire = try wireObject(WebOSClient.registerMessage(clientKey: "abc123"))
        let payload = try XCTUnwrap(wire["payload"] as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["forcePairing", "pairingType", "client-key", "manifest"])
        XCTAssertEqual(payload["forcePairing"] as? Bool, false)
        XCTAssertEqual(payload["pairingType"] as? String, "PROMPT")
        XCTAssertEqual(payload["client-key"] as? String, "abc123")
    }

    func testRegisterWithoutKeySendsEmptyClientKey() throws {
        for key: String? in [nil, ""] {
            let wire = try wireObject(WebOSClient.registerMessage(clientKey: key))
            let payload = try XCTUnwrap(wire["payload"] as? [String: Any])
            XCTAssertEqual(payload["client-key"] as? String, "")
        }
    }

    func testRegisterManifestKeepsAppIdentityAndScreenPermissions() throws {
        let wire = try wireObject(WebOSClient.registerMessage(clientKey: nil))
        let payload = try XCTUnwrap(wire["payload"] as? [String: Any])
        let manifest = try XCTUnwrap(payload["manifest"] as? [String: Any])
        XCTAssertEqual(manifest["manifestVersion"] as? Int, 1)

        let signed = try XCTUnwrap(manifest["signed"] as? [String: Any])
        XCTAssertEqual(signed["appId"] as? String, "com.lgtvcompanion.mac")

        // Without these the TV answers "401 insufficient permissions" to
        // turnOffScreen / turnOnScreen (see the comment at the manifest).
        let permissions = try XCTUnwrap(manifest["permissions"] as? [String])
        for needed in ["CONTROL_TV_SCREEN", "CONTROL_TV_POWER", "CONTROL_AUDIO", "CONTROL_WOL"] {
            XCTAssertTrue(permissions.contains(needed), needed)
        }
        XCTAssertEqual((manifest["signatures"] as? [[String: Any]])?.count, 1)
    }

    // MARK: Request

    func testRequestWithoutPayload() throws {
        let message = WebOSClient.requestMessage(uri: "ssap://audio/getVolume", payload: nil, id: "request_7")
        let wire = try wireObject(message)
        XCTAssertEqual(wire["type"] as? String, "request")
        XCTAssertEqual(wire["uri"] as? String, "ssap://audio/getVolume")
        XCTAssertEqual(wire["id"] as? String, "request_7")
        XCTAssertNil(wire["payload"], "no payload key at all, not null")
    }

    func testRequestWithPayload() throws {
        let message = WebOSClient.requestMessage(uri: "ssap://tv/switchInput",
                                                 payload: ["inputId": "HDMI_2"], id: "request_8")
        let wire = try wireObject(message)
        XCTAssertEqual(Set(wire.keys), ["type", "uri", "id", "payload"])
        XCTAssertEqual((wire["payload"] as? [String: Any])?["inputId"] as? String, "HDMI_2")
    }
}
