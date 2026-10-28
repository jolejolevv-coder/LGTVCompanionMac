import XCTest
@testable import LGTVCompanionShared

final class WakeOnLANTests: XCTestCase {

    private let mac: [UInt8] = [0x80, 0x5B, 0x65, 0xD6, 0x27, 0xE0]

    // MARK: Magic packet

    func testMagicPacketIsSixFFThenSixteenMACs() {
        let packet = [UInt8](WakeOnLAN.createMagicPacket(macBytes: mac))

        XCTAssertEqual(packet.count, 6 + 16 * 6, "102 bytes")
        XCTAssertEqual(Array(packet[0..<6]), [UInt8](repeating: 0xFF, count: 6))
        for repetition in 0..<16 {
            let start = 6 + repetition * 6
            XCTAssertEqual(Array(packet[start..<start + 6]), mac, "repetition \(repetition)")
        }
    }

    // MARK: MAC parsing

    func testParsesAllSupportedMACForms() throws {
        let forms = ["80:5B:65:D6:27:E0", "80-5b-65-d6-27-e0", "805B65D627E0", "80:5b:65:D6:27:e0"]
        for form in forms {
            XCTAssertEqual(try WakeOnLAN.parseMacAddress(form), mac, form)
        }
    }

    func testRejectsMalformedMACsWhenParsing() {
        let malformed = ["", "80:5B:65:D6:27", "80:5B:65:D6:27:E0:11", "80:5B:65:D6:27:GG", "not a mac"]
        for text in malformed {
            XCTAssertThrowsError(try WakeOnLAN.parseMacAddress(text), text)
        }
    }

    // MARK: Validation

    func testMACValidationTable() {
        let cases: [(String, Bool)] = [
            ("80:5B:65:D6:27:E0", true),
            ("80-5b-65-d6-27-e0", true),
            ("80:5b:65:D6:27:e0", true),
            ("805B65D627E0", false),      // validation wants separators, parsing does not
            ("80:5B:65:D6:27", false),
            ("80:5B:65:D6:27:E0:11", false),
            ("80:5B:65:D6:27:GG", false),
            ("80:5B-65:D6-27:E0", true),  // mixed separators are accepted today
            ("80:5B:65:D6:27:E0 ", false),
            ("", false),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(WakeOnLAN.isValidMacAddress(text), expected, "\"\(text)\"")
        }
    }

    func testIPValidationTable() {
        let cases: [(String, Bool)] = [
            ("192.168.1.20", true),
            ("0.0.0.0", true),
            ("255.255.255.255", true),
            ("192.168.1.256", false),
            ("192.168.1", false),
            ("192.168.1.1.", false),
            (".192.168.1.1", false),
            ("1.2.3.+4", false),
            ("192.168.1.x", false),
            ("::1", false),
            (" 192.168.1.1", false),
            ("", false),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(WakeOnLAN.isValidIPAddress(text), expected, "\"\(text)\"")
        }
    }
}
