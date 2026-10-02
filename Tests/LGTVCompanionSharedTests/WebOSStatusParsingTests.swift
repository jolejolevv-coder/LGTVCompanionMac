import XCTest
@testable import LGTVCompanionShared

final class WebOSStatusParsingTests: XCTestCase {

    private func json(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    /// Subscription answer of an LG OLED42C2 on optical output, 2026-10-02.
    func testParsesNestedAudioStatusFromRealTv() {
        let payload = json("""
        {"returnValue": true, "volumeStatus": {"volumeLimitable": false, "activeStatus": true,
         "maxVolume": 100, "soundOutput": "external_optical", "volume": 10, "mode": "normal",
         "externalDeviceControl": false, "muteStatus": false, "volumeSyncable": false,
         "adjustVolume": false}, "callerId": "secondscreen.client"}
        """)
        let audio = WebOSClient.parseAudioStatus(payload)
        XCTAssertEqual(audio.volume, 10)
        XCTAssertEqual(audio.muted, false)
        XCTAssertEqual(audio.adjustable, false)
    }

    func testParsesAdjustableOutput() {
        let audio = WebOSClient.parseAudioStatus(json("""
        {"volumeStatus": {"volume": 23, "muteStatus": true, "adjustVolume": true}}
        """))
        XCTAssertEqual(audio.volume, 23)
        XCTAssertEqual(audio.muted, true)
        XCTAssertEqual(audio.adjustable, true)
    }

    func testParsesFlatPayloadOfOlderFirmware() {
        let audio = WebOSClient.parseAudioStatus(json(#"{"volume": 7, "muted": true}"#))
        XCTAssertEqual(audio.volume, 7)
        XCTAssertEqual(audio.muted, true)
        XCTAssertNil(audio.adjustable, "older firmware does not report adjustVolume")
    }

    func testMissingAudioPayloadYieldsNoValues() {
        let audio = WebOSClient.parseAudioStatus(nil)
        XCTAssertNil(audio.volume)
        XCTAssertNil(audio.muted)
        XCTAssertNil(audio.adjustable)
    }

    func testParsesPowerState() {
        XCTAssertEqual(WebOSClient.parsePowerState(json(
            #"{"state": "Active", "subscribed": true, "returnValue": true}"#)), "Active")
        XCTAssertEqual(WebOSClient.parsePowerState(json(
            #"{"state": "Screen Off", "processing": "Screen On"}"#)), "Screen Off")
    }

    func testPowerStateIsNilWhenNotReported() {
        XCTAssertNil(WebOSClient.parsePowerState(json(#"{"returnValue": true}"#)))
        XCTAssertNil(WebOSClient.parsePowerState(nil))
    }
}
