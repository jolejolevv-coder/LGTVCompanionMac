import XCTest
@testable import LGTVCompanionShared

final class SoftwareVolumeTests: XCTestCase {

    // MARK: Gain curve

    func testFullLevelIsUnityGain() {
        XCTAssertEqual(SoftwareVolume.gain(forLevel: 1, muted: false), 1)
    }

    func testZeroLevelIsSilent() {
        XCTAssertEqual(SoftwareVolume.gain(forLevel: 0, muted: false), 0)
    }

    func testMuteIsSilentAtAnyLevel() {
        XCTAssertEqual(SoftwareVolume.gain(forLevel: 1, muted: true), 0)
        XCTAssertEqual(SoftwareVolume.gain(forLevel: 0.5, muted: true), 0)
    }

    func testGainNeverAmplifies() {
        XCTAssertEqual(SoftwareVolume.gain(forLevel: 3, muted: false), 1)
        XCTAssertEqual(SoftwareVolume.gain(forLevel: -1, muted: false), 0)
    }

    func testCurveIsCubicAndMonotonic() {
        XCTAssertEqual(SoftwareVolume.gain(forLevel: 0.5, muted: false), 0.125, accuracy: 0.0001)
        var previous: Float = -1
        for step in 0...SoftwareVolume.stepCount {
            let gain = SoftwareVolume.gain(forLevel: Double(step) / Double(SoftwareVolume.stepCount), muted: false)
            XCTAssertGreaterThan(gain, previous)
            previous = gain
        }
    }

    // MARK: Key steps

    func testSixteenStepsFromSilentToFull() {
        var level = 0.0
        for _ in 0..<SoftwareVolume.stepCount {
            level = SoftwareVolume.stepped(level, by: +1)
        }
        XCTAssertEqual(level, 1)
    }

    func testStepsClampAtBothEnds() {
        XCTAssertEqual(SoftwareVolume.stepped(1, by: +1), 1)
        XCTAssertEqual(SoftwareVolume.stepped(0, by: -1), 0)
    }

    func testStepSnapsSliderValueToGrid() {
        // 0.52 sits between steps 8 and 9; rounding picks 8, one up is 9/16.
        XCTAssertEqual(SoftwareVolume.stepped(0.52, by: +1), 9.0 / 16.0)
    }

    func testUpThenDownReturnsToStart() {
        let start = 5.0 / 16.0
        XCTAssertEqual(SoftwareVolume.stepped(SoftwareVolume.stepped(start, by: +1), by: -1), start)
    }

    // MARK: Mode selection

    func testTakesOverWhenTvCannotAdjustAndSoundGoesToDisplay() {
        XCTAssertTrue(SoftwareVolume.shouldControl(enabled: true, tvCanAdjustVolume: false,
                                                   outputIsDigitalDisplay: true))
    }

    func testLeavesVolumeToTvWhenTvCanAdjust() {
        XCTAssertFalse(SoftwareVolume.shouldControl(enabled: true, tvCanAdjustVolume: true,
                                                    outputIsDigitalDisplay: true))
    }

    func testUnknownTvAnswerKeepsOldBehavior() {
        XCTAssertFalse(SoftwareVolume.shouldControl(enabled: true, tvCanAdjustVolume: nil,
                                                    outputIsDigitalDisplay: true))
    }

    func testStaysOutWhenSoundGoesToHeadphones() {
        XCTAssertFalse(SoftwareVolume.shouldControl(enabled: true, tvCanAdjustVolume: false,
                                                    outputIsDigitalDisplay: false))
    }

    func testRespectsTheSettingsSwitch() {
        XCTAssertFalse(SoftwareVolume.shouldControl(enabled: false, tvCanAdjustVolume: false,
                                                    outputIsDigitalDisplay: true))
    }
}
