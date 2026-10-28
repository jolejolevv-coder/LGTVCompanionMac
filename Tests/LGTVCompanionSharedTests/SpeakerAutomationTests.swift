import XCTest
@testable import LGTVCompanionShared

/// The speaker controller stays switched off in these tests (its "enabled"
/// flag lives in the real defaults and is not set there by the tests), so no
/// Bluetooth is touched. What is tested is the settings logic around it.
@MainActor
final class SpeakerAutomationTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "lgtvcompanion.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeAutomation() -> (SpeakerAutomation, EdifierSpeakerController) {
        let speakers = EdifierSpeakerController()
        return (SpeakerAutomation(speakers: speakers, defaults: defaults), speakers)
    }

    func testFreshInstallDefaults() {
        let (automation, speakers) = makeAutomation()
        XCTAssertEqual(automation.myEQ, SpeakerSoundLibrary.flatGains)
        XCTAssertFalse(automation.nightModeActive)
        XCTAssertFalse(automation.nightScheduleEnabled)
        XCTAssertEqual(automation.nightSchedule, NightSchedule(startMinutes: 22 * 60, endMinutes: 7 * 60))
        XCTAssertEqual(automation.nightSubOut, .low)
        XCTAssertFalse(automation.wakeInputEnabled)
        XCTAssertEqual(automation.wakeInput, .optical)
        XCTAssertNil(speakers.volumeLimit)
        XCTAssertNil(automation.currentSound, "unknown until the speakers reported it")
    }

    func testNightModeCapsTheVolumeAndReleasesItAgain() {
        let (automation, speakers) = makeAutomation()
        automation.setNightVolumeLimit(12)

        automation.setNightMode(true)
        XCTAssertEqual(speakers.volumeLimit, 12)

        automation.setNightMode(false)
        XCTAssertNil(speakers.volumeLimit)
    }

    func testChangingTheLimitDuringNightAppliesAtOnce() {
        let (automation, speakers) = makeAutomation()
        automation.setNightMode(true)
        automation.setNightVolumeLimit(20)
        XCTAssertEqual(speakers.volumeLimit, 20)
    }

    func testVolumeLimitStaysWithinTheSpeakersRange() {
        let (automation, _) = makeAutomation()
        automation.setNightVolumeLimit(500)
        XCTAssertEqual(automation.nightVolumeLimit, EdifierProtocol.defaultMaxVolume)
        automation.setNightVolumeLimit(-4)
        XCTAssertEqual(automation.nightVolumeLimit, 1, "a limit of zero would be a mute, not a cap")
    }

    func testSettingsSurviveARestart() {
        let (first, _) = makeAutomation()
        first.setNightMode(true)
        first.setNightSchedule(startMinutes: 21 * 60 + 30, endMinutes: 6 * 60)
        first.setNightVolumeLimit(9)
        first.setNightSubOut(.medium)
        first.setWakeInput(enabled: true)
        first.setWakeInput(.hdmi)
        first.setMyEQBand(index: 0, gainDB: 2.5)

        let (second, speakers) = makeAutomation()
        XCTAssertTrue(second.nightModeActive)
        XCTAssertEqual(speakers.volumeLimit, 9, "the cap must be back in force right after launch")
        XCTAssertEqual(second.nightSchedule, NightSchedule(startMinutes: 21 * 60 + 30, endMinutes: 6 * 60))
        XCTAssertEqual(second.nightSubOut, .medium)
        XCTAssertTrue(second.wakeInputEnabled)
        XCTAssertEqual(second.wakeInput, .hdmi)
        XCTAssertEqual(second.myEQ.first, 2.5)
    }

    func testMyEQBandIsSnappedAndIgnoresUnknownBands() {
        let (automation, _) = makeAutomation()
        automation.setMyEQBand(index: 2, gainDB: 1.3)
        XCTAssertEqual(automation.myEQ[2], 1.5)
        automation.setMyEQBand(index: 3, gainDB: 99)
        XCTAssertEqual(automation.myEQ[3], 3)

        let before = automation.myEQ
        automation.setMyEQBand(index: 42, gainDB: 1)
        XCTAssertEqual(automation.myEQ, before)
    }

    func testResetMyEQGoesBackToFlat() {
        let (automation, _) = makeAutomation()
        automation.setMyEQBand(index: 0, gainDB: 3)
        automation.resetMyEQ()
        XCTAssertEqual(automation.myEQ, SpeakerSoundLibrary.flatGains)
    }

    func testCorruptStoredCurveFallsBackToFlat() {
        defaults.set([1.0, 2.0], forKey: "lgtvcompanion.speakers.myEQ")   // wrong band count
        let (automation, _) = makeAutomation()
        XCTAssertEqual(automation.myEQ, SpeakerSoundLibrary.flatGains)
    }
}

/// Night schedule 22:00 until 08:00, checked at chosen times of day.
@MainActor
final class NightScheduleBehaviorTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var calendar = Calendar.current

    override func setUp() async throws {
        suiteName = "lgtvcompanion.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    /// A fresh app instance on the same stored settings, like after a restart,
    /// starting at the given time of day.
    private func launch(at time: Date? = nil) -> SpeakerAutomation {
        let start = time ?? at(12)
        return SpeakerAutomation(speakers: EdifierSpeakerController(), defaults: defaults, clock: { start })
    }

    private func scheduled() -> SpeakerAutomation {
        let automation = launch()
        automation.setNightSchedule(startMinutes: 22 * 60, endMinutes: 8 * 60)
        automation.setNightSchedule(enabled: true)
        return automation
    }

    func testTurnsOnAtTenAndOffAtEightWhileRunning() {
        let automation = scheduled()
        automation.checkSchedule(now: at(21, 59))
        XCTAssertFalse(automation.nightModeActive)
        automation.checkSchedule(now: at(22, 0))
        XCTAssertTrue(automation.nightModeActive)
        automation.checkSchedule(now: at(7, 59))
        XCTAssertTrue(automation.nightModeActive)
        automation.checkSchedule(now: at(8, 0))
        XCTAssertFalse(automation.nightModeActive)
    }

    /// The reported bug: Mac off over night, app starts at 08:30.
    func testRestartAfterEightTurnsScheduledNightModeOff() {
        let evening = scheduled()
        evening.checkSchedule(now: at(23, 35))
        XCTAssertTrue(evening.nightModeActive)

        // Starting at 08:30 alone must turn it off, without waiting for a timer.
        let morning = launch(at: at(8, 30))
        XCTAssertFalse(morning.nightModeActive)
    }

    func testRestartDuringTheNightKeepsNightModeOn() {
        let evening = scheduled()
        evening.checkSchedule(now: at(23, 0))

        let later = launch(at: at(2, 0))
        XCTAssertTrue(later.nightModeActive)
    }

    func testManualOffAtNightIsNotUndoneUntilTheNextEvening() {
        let automation = scheduled()
        automation.checkSchedule(now: at(22, 0))
        automation.setNightMode(false)

        automation.checkSchedule(now: at(23, 0))
        XCTAssertFalse(automation.nightModeActive, "a manual off must stick for the rest of the night")
        let restarted = launch(at: at(1, 0))
        XCTAssertFalse(restarted.nightModeActive, "also across a restart")

        restarted.checkSchedule(now: at(9, 0))
        restarted.checkSchedule(now: at(22, 0))
        XCTAssertTrue(restarted.nightModeActive, "the next evening turns it on again")
    }

    func testManualOnDuringTheDayIsNotTurnedOffByTheSchedule() {
        let automation = scheduled()
        automation.checkSchedule(now: at(14, 0))
        automation.setNightMode(true)
        automation.checkSchedule(now: at(15, 0))
        XCTAssertTrue(automation.nightModeActive)
    }

    func testFirstLaunchInsideTheWindowTurnsNightModeOn() {
        let automation = scheduled()
        automation.checkSchedule(now: at(23, 0))
        XCTAssertTrue(automation.nightModeActive)
    }

    func testDisabledScheduleDoesNothing() {
        let automation = launch()
        automation.setNightSchedule(enabled: false)
        automation.checkSchedule(now: at(23, 0))
        XCTAssertFalse(automation.nightModeActive)
    }
}
