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

final class EdifierSoundProtocolTests: XCTestCase {

    private func bytes(_ hex: String) -> Data {
        Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
    }

    // MARK: Input, compared with the documented frames

    func testInputSettersMatchReference() {
        XCTAssertEqual(EdifierProtocol.setInput(.bluetooth), bytes("AA EC 62 00 02 1D 01 18"))
        XCTAssertEqual(EdifierProtocol.setInput(.usb), bytes("AA EC 62 00 02 1D 02 19"))
        XCTAssertEqual(EdifierProtocol.setInput(.hdmi), bytes("AA EC 62 00 02 1D 03 1A"))
        XCTAssertEqual(EdifierProtocol.setInput(.optical), bytes("AA EC 62 00 02 1D 04 1B"))
        XCTAssertEqual(EdifierProtocol.setInput(.aux), bytes("AA EC 62 00 02 1D 05 1C"))
    }

    func testParsesInputReplyFromRealSpeaker() {
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB EC 61 00 02 1D 04 2B")), [.input(.optical)])
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB EC 61 00 02 1D 01 28")), [.input(.bluetooth)])
    }

    func testInputReplyOfAnotherGroupIsNotTrusted() {
        // Group 0F is the M60's; its source numbers mean something else.
        let frame = Data([0xBB, 0xEC, 0x61, 0x00, 0x02, 0x0F, 0x04])
        let reply = EdifierProtocol.parse(frame + Data([EdifierProtocol.checksum(frame)]))
        XCTAssertEqual(reply, [.other(app: 0xEC, opcode: 0x61)])
    }

    // MARK: EQ preset

    func testEQPresetSettersMatchReference() {
        XCTAssertEqual(EdifierProtocol.setEQPreset(.classic), bytes("AA EC C4 00 01 00 5B"))
        XCTAssertEqual(EdifierProtocol.setEQPreset(.dynamic), bytes("AA EC C4 00 01 02 5D"))
        XCTAssertEqual(EdifierProtocol.setEQPreset(.custom), bytes("AA EC C4 00 01 03 5E"))
        XCTAssertEqual(EdifierProtocol.queryEQPreset(), bytes("AA EC D5 00 00 6B"))
    }

    func testParsesEQPresetReply() {
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB EC D5 00 01 03 80")), [.eqPreset(.custom)])
        XCTAssertEqual(EdifierProtocol.parse(bytes("BB EC D5 00 01 00 7D")), [.eqPreset(.classic)])
    }

    // MARK: Custom EQ

    func testEQBandSetterMatchesReference() {
        // Reference: band 0 (62 Hz) to +0.5 dB and back to 0 dB.
        XCTAssertEqual(EdifierProtocol.setEQBand(index: 0, gainDB: 0.5), bytes("AA EC 44 00 04 00 00 3E 07 23"))
        XCTAssertEqual(EdifierProtocol.setEQBand(index: 0, gainDB: 0), bytes("AA EC 44 00 04 00 00 3E 06 22"))
        XCTAssertEqual(EdifierProtocol.queryCustomEQ(), bytes("AA EC 43 00 00 D9"))
    }

    func testEQBandCarriesItsFrequency() throws {
        let frame = try XCTUnwrap(EdifierProtocol.setEQBand(index: 8, gainDB: 3))   // 16 kHz = 3E 80
        XCTAssertEqual([UInt8](frame)[5...8], [0x08, 0x3E, 0x80, 0x0C])
    }

    func testEQBandRejectsUnknownIndex() {
        XCTAssertNil(EdifierProtocol.setEQBand(index: 9, gainDB: 0))
        XCTAssertNil(EdifierProtocol.setEQBand(index: -1, gainDB: 0))
    }

    func testGainIsClampedAndSnappedToHalfDecibels() {
        XCTAssertEqual(EdifierProtocol.snappedGain(7), 3)
        XCTAssertEqual(EdifierProtocol.snappedGain(-9), -3)
        XCTAssertEqual(EdifierProtocol.snappedGain(1.3), 1.5)
        XCTAssertEqual(EdifierProtocol.snappedGain(-0.2), 0)
        XCTAssertEqual(EdifierProtocol.gainCode(for: -3), 0)
        XCTAssertEqual(EdifierProtocol.gainCode(for: 0), 6)
        XCTAssertEqual(EdifierProtocol.gainCode(for: 3), 12)
    }

    /// Custom EQ of the user's M90 (firmware 1.5.1), read on 2026-10-02:
    /// +0.5 dB at 62 Hz, flat otherwise, profile name "Sound Effects".
    func testParsesCustomEQFromRealSpeaker() {
        let reply = bytes("""
        BB EC 43 00 37 10 09 00 00 3E 07 01 00 7D 06 02 00 FA 06 03 01 F4 06 04 03 E8 06 \
        05 07 D0 06 06 0F A0 06 07 1F 40 06 08 3E 80 06 81 F2 BF 6A 53 6F 75 6E 64 20 45 \
        66 66 65 63 74 73 52
        """)
        XCTAssertEqual(EdifierProtocol.parse(reply), [.customEQ([0.5, 0, 0, 0, 0, 0, 0, 0, 0])])
    }

    func testCustomEQWithUnexpectedLayoutIsRejected() {
        // Six bands of the M60 layout must not be read as nine M90 bands.
        var payload: [UInt8] = [0x03, 0x06]
        payload += [UInt8](repeating: 0x06, count: 40)
        var frame: [UInt8] = [0xBB, 0xEC, 0x43, 0x00, UInt8(payload.count)] + payload
        frame.append(EdifierProtocol.checksum(frame))
        XCTAssertEqual(EdifierProtocol.parse(Data(frame)), [.other(app: 0xEC, opcode: 0x43)])
    }
}

final class SpeakerSoundTests: XCTestCase {

    func testBuiltInCurvesFitTheSpeaker() {
        for curve in SpeakerSoundLibrary.builtInCurves {
            XCTAssertEqual(curve.gains.count, EdifierProtocol.eqBandFrequencies.count, curve.name)
            for gain in curve.gains {
                XCTAssertEqual(EdifierProtocol.snappedGain(gain), gain, "\(curve.name) must use valid steps")
            }
        }
    }

    func testBuiltInCurvesAreDistinct() {
        XCTAssertNotEqual(SpeakerSoundLibrary.techno.gains, SpeakerSoundLibrary.hipHop.gains)
        XCTAssertNotEqual(SpeakerSoundLibrary.techno.gains, SpeakerSoundLibrary.flatGains)
    }

    func testIdentifiesSpeakerPresets() {
        XCTAssertEqual(SpeakerSoundLibrary.identify(preset: .dynamic, customEQ: nil), .preset(.dynamic))
        // The custom curve is irrelevant while another preset is selected.
        XCTAssertEqual(SpeakerSoundLibrary.identify(preset: .classic, customEQ: SpeakerSoundLibrary.techno.gains),
                       .preset(.classic))
    }

    func testIdentifiesAppCurvesInTheCustomSlot() {
        XCTAssertEqual(SpeakerSoundLibrary.identify(preset: .custom, customEQ: SpeakerSoundLibrary.techno.gains),
                       .curve(SpeakerSoundLibrary.technoID))
        XCTAssertEqual(SpeakerSoundLibrary.identify(preset: .custom, customEQ: SpeakerSoundLibrary.hipHop.gains),
                       .curve(SpeakerSoundLibrary.hipHopID))
    }

    func testUnknownOrMissingCustomCurveCountsAsMyEQ() {
        XCTAssertEqual(SpeakerSoundLibrary.identify(preset: .custom, customEQ: [0.5, 0, 0, 0, 0, 0, 0, 0, 0]),
                       .curve(SpeakerSoundLibrary.myEQID))
        XCTAssertEqual(SpeakerSoundLibrary.identify(preset: .custom, customEQ: nil),
                       .curve(SpeakerSoundLibrary.myEQID))
    }

    func testGainsForEachChoice() {
        let mine = [1.0, 0, 0, 0, 0, 0, 0, 0, -1]
        XCTAssertNil(SpeakerSoundLibrary.gains(for: .preset(.classic), myEQ: mine))
        XCTAssertEqual(SpeakerSoundLibrary.gains(for: .curve(SpeakerSoundLibrary.myEQID), myEQ: mine), mine)
        XCTAssertEqual(SpeakerSoundLibrary.gains(for: .curve(SpeakerSoundLibrary.technoID), myEQ: mine),
                       SpeakerSoundLibrary.techno.gains)
        XCTAssertNil(SpeakerSoundLibrary.gains(for: .curve("does-not-exist"), myEQ: mine))
    }

    func testEveryMenuEntryHasAName() {
        let names = SpeakerSoundLibrary.menuOrder.map(SpeakerSoundLibrary.name(of:))
        XCTAssertEqual(names, ["Classic", "Monitor", "Dynamic", "Techno", "Hip-Hop", "My EQ"])
    }

    // MARK: Night schedule

    func testScheduleAcrossMidnight() {
        let night = NightSchedule(startMinutes: 22 * 60, endMinutes: 7 * 60)
        XCTAssertTrue(night.contains(minutesOfDay: 22 * 60))
        XCTAssertTrue(night.contains(minutesOfDay: 23 * 60 + 59))
        XCTAssertTrue(night.contains(minutesOfDay: 0))
        XCTAssertTrue(night.contains(minutesOfDay: 6 * 60 + 59))
        XCTAssertFalse(night.contains(minutesOfDay: 7 * 60))
        XCTAssertFalse(night.contains(minutesOfDay: 12 * 60))
        XCTAssertFalse(night.contains(minutesOfDay: 21 * 60 + 59))
    }

    func testScheduleWithinOneDay() {
        let nap = NightSchedule(startMinutes: 13 * 60, endMinutes: 15 * 60)
        XCTAssertTrue(nap.contains(minutesOfDay: 13 * 60))
        XCTAssertTrue(nap.contains(minutesOfDay: 14 * 60 + 30))
        XCTAssertFalse(nap.contains(minutesOfDay: 15 * 60))
        XCTAssertFalse(nap.contains(minutesOfDay: 3 * 60))
    }

    func testEmptyScheduleNeverMatches() {
        let empty = NightSchedule(startMinutes: 22 * 60, endMinutes: 22 * 60)
        XCTAssertFalse(empty.contains(minutesOfDay: 22 * 60))
        XCTAssertFalse(empty.contains(minutesOfDay: 0))
    }

    func testMinutesOfDayFromDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 22, minute: 15))!
        XCTAssertEqual(NightSchedule.minutesOfDay(for: date, calendar: calendar), 22 * 60 + 15)
    }
}
