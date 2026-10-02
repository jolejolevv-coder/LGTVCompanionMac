import XCTest
@testable import LGTVCompanionShared

final class EdifierProtocolTests: XCTestCase {

    private func bytes(_ hex: String) -> Data {
        Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
    }

    // MARK: Requests, compared with the documented frames

    func testQueryFramesMatchReference() {
        XCTAssertEqual(EdifierProtocol.queryVolume(), bytes("AA EC 66 00 00 FC"))
        XCTAssertEqual(EdifierProtocol.queryName(), bytes("AA EC C9 00 00 5F"))
        XCTAssertEqual(EdifierProtocol.querySubOut(), bytes("AA ED 13 00 00 AA"))
    }

    func testSubOutSettersMatchReference() {
        XCTAssertEqual(EdifierProtocol.setSubOut(.low), bytes("AA ED 14 00 02 00 00 AD"))
        XCTAssertEqual(EdifierProtocol.setSubOut(.medium), bytes("AA ED 14 00 02 00 01 AE"))
        XCTAssertEqual(EdifierProtocol.setSubOut(.high), bytes("AA ED 14 00 02 00 02 AF"))
    }

    func testSetVolumeUsesDocumentedChecksumRule() {
        // Reference: AA EC 67 00 01 <V> <(FE + V) mod 256>
        for volume in [0, 8, 25, 50] {
            let expected = Data([0xAA, 0xEC, 0x67, 0x00, 0x01, UInt8(volume), UInt8((0xFE + volume) % 256)])
            XCTAssertEqual(EdifierProtocol.setVolume(volume), expected)
        }
    }

    func testSetVolumeClampsToTheSpeakersRange() {
        XCTAssertEqual(EdifierProtocol.setVolume(99), EdifierProtocol.setVolume(50))
        XCTAssertEqual(EdifierProtocol.setVolume(-3), EdifierProtocol.setVolume(0))
        XCTAssertEqual(EdifierProtocol.setVolume(40, maximum: 30), EdifierProtocol.setVolume(30))
    }

    // MARK: Replies, captured from a real M90 (firmware 1.5.1) on 2026-10-02

    func testParsesVolumeReply() {
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB EC 66 00 02 32 32 73")),
                       [.volume(maximum: 50, current: 50)])
    }

    func testParsesSubOutReply() {
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB ED 13 00 02 00 01 BE")), [.subOut(.medium)])
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB ED 13 00 02 00 02 BF")), [.subOut(.high)])
    }

    func testParsesNameReply() {
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB EC C9 00 0B 45 44 49 46 49 45 52 20 4D 39 30 49")),
                       [.name("EDIFIER M90")])
    }

    func testOtherValidFramesAreReportedButCarryNoState() {
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB EC C6 00 03 01 05 01 77")),
                       [.other(app: 0xEC, opcode: 0xC6)])
        // Acknowledgement with the CC header.
        XCTAssertEqual(EdifierProtocol.parse(bytes("CC EC CA 00 01 01 84")),
                       [.other(app: 0xEC, opcode: 0xCA)])
    }

    func testParsesTwoFramesInOneNotification() {
        let both = bytes("BB EC 66 00 02 32 08 49") + bytes("BB ED 13 00 02 00 00 BD")
        XCTAssertEqual(EdifierProtocol.parse(both), [.volume(maximum: 50, current: 8), .subOut(.low)])
    }

    // MARK: Malformed input

    func testRejectsWrongChecksum() {
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB EC 66 00 02 32 32 74")), [])
    }

    func testRejectsTruncatedAndForeignData() {
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB EC 66 00 02 32")), [])
        XCTAssertEqual(EdifierProtocol.parse(bytes("AA EC 66 00 00 FC")), [])   // a request, not a reply
        XCTAssertEqual(EdifierProtocol.parse(Data()), [])
    }

    func testUnknownSubOutLevelIsNotMappedToAKnownOne() {
        // Level 07 with a valid checksum must not turn into low/medium/high.
        let frame = Data([0xBB, 0xED, 0x13, 0x00, 0x02, 0x00, 0x07])
        let withChecksum = frame + Data([EdifierProtocol.checksum(frame)])
        XCTAssertEqual(EdifierProtocol.parse(withChecksum), [.other(app: 0xED, opcode: 0x13)])
    }

    // MARK: Hand-over from software volume

    func testHandOverScalesSpeakerVolumeByTheSoftwareLevel() {
        XCTAssertEqual(SoftwareVolume.handOverVolume(speakerVolume: 50, softwareLevel: 0.5), 25)
        XCTAssertEqual(SoftwareVolume.handOverVolume(speakerVolume: 50, softwareLevel: 1), 50)
        XCTAssertEqual(SoftwareVolume.handOverVolume(speakerVolume: 50, softwareLevel: 0), 0)
    }

    func testHandOverRoundsDownSoItNeverGetsLouder() {
        XCTAssertEqual(SoftwareVolume.handOverVolume(speakerVolume: 33, softwareLevel: 0.9375), 30)
        XCTAssertLessThanOrEqual(SoftwareVolume.handOverVolume(speakerVolume: 7, softwareLevel: 2), 7)
    }
}
