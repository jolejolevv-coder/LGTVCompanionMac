import XCTest
@testable import LGTVCompanionShared

/// In-memory stand-in for the keychain.
private final class MemoryKeyStore: PairingKeyStoring {
    var keys: [UUID: String] = [:]
    func save(_ key: String, for deviceID: UUID) -> Bool { keys[deviceID] = key; return true }
    func load(for deviceID: UUID) -> String? { keys[deviceID] }
    func delete(for deviceID: UUID) { keys[deviceID] = nil }
}

/// "Reset All Settings" must leave nothing of the app behind: no device, no
/// pairing key, no stored option, no speaker setting.
@MainActor
final class ResetAllSettingsTests: XCTestCase {

    private static let appKeyPrefix = "lgtvcompanion."

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var keyStore: MemoryKeyStore!

    override func setUp() {
        suiteName = "lgtvcompanion.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        keyStore = MemoryKeyStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func appKeys() -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(Self.appKeyPrefix) }
    }

    /// A manager whose stored state is as far from a fresh install as the
    /// test can get without touching Bluetooth, the keychain or macOS.
    private func makeUsedManager() -> DeviceManager {
        // Speaker settings written by an earlier run. The key names are the
        // storage format, a rename would need a migration anyway.
        defaults.set(true, forKey: "lgtvcompanion.speakers.enabled")
        defaults.set("peripheral-id", forKey: "lgtvcompanion.speakers.peripheral")
        defaults.set(Array(repeating: 1.5, count: EdifierProtocol.eqBandFrequencies.count),
                     forKey: "lgtvcompanion.speakers.myEQ")
        defaults.set(true, forKey: "lgtvcompanion.speakers.nightActive")
        defaults.set(true, forKey: "lgtvcompanion.speakers.nightScheduleEnabled")
        defaults.set(5, forKey: "lgtvcompanion.speakers.nightVolumeLimit")
        defaults.set(2, forKey: "lgtvcompanion.speakers.nightSubOut")
        defaults.set(true, forKey: "lgtvcompanion.speakers.wakeInputEnabled")
        defaults.set(1, forKey: "lgtvcompanion.speakers.wakeInput")

        let manager = DeviceManager(pairingKeyStore: keyStore, userDefaults: defaults)
        manager.addDevice(WebOSDevice(name: "TV", ipAddress: "192.168.1.20",
                                      macAddress: "80:5B:65:D6:27:E0", pairingKey: "secret"))
        manager.updateUserIdleSettings(enabled: true, timeout: 900)
        manager.setAppAllowed(AssertingApp(bundleID: "com.example.player", name: "Player"), allowed: true)
        manager.setSoftwareVolumeEnabled(false)
        manager.setSoftwareVolume(level: 0.25)
        manager.flushPendingSettings()
        return manager
    }

    func testResetLeavesNoStoredStateBehind() {
        let manager = makeUsedManager()
        XCTAssertFalse(appKeys().isEmpty, "the test must start from a used state")

        manager.resetAllSettings()

        XCTAssertEqual(appKeys(), [], "keys left behind")
    }

    func testResetRemovesTVsAndTheirPairingKeys() {
        let manager = makeUsedManager()
        XCTAssertEqual(keyStore.keys.count, 1)

        manager.resetAllSettings()

        XCTAssertTrue(manager.devices.isEmpty)
        XCTAssertTrue(keyStore.keys.isEmpty)
    }

    func testResetRestoresTheDefaultValues() {
        let manager = makeUsedManager()

        manager.resetAllSettings()

        XCTAssertFalse(manager.userIdleEnabled)
        XCTAssertEqual(manager.userIdleTimeout, DeviceManager.defaultUserIdleTimeout)
        XCTAssertTrue(manager.assertionAllowlist.isEmpty)
        XCTAssertFalse(manager.mediaKeysEnabled)
        XCTAssertTrue(manager.softwareVolumeEnabled)
        XCTAssertEqual(manager.softwareVolumeLevel, 1)
        XCTAssertFalse(manager.softwareVolumeMuted)

        XCTAssertFalse(manager.speakers.isEnabled)
        XCTAssertFalse(manager.speakers.hasKnownSpeaker)
        XCTAssertNil(manager.speakers.volumeLimit)
        let automation = manager.speakerAutomation
        XCTAssertEqual(automation.myEQ, SpeakerSoundLibrary.flatGains)
        XCTAssertFalse(automation.nightModeActive)
        XCTAssertFalse(automation.nightScheduleEnabled)
        XCTAssertEqual(automation.nightSchedule, NightSchedule(startMinutes: 22 * 60, endMinutes: 7 * 60))
        XCTAssertEqual(automation.nightVolumeLimit, 15)
        XCTAssertEqual(automation.nightSubOut, .low)
        XCTAssertFalse(automation.wakeInputEnabled)
        XCTAssertEqual(automation.wakeInput, .optical)
    }

    func testAFreshManagerAfterResetStartsEmpty() {
        makeUsedManager().resetAllSettings()

        let fresh = DeviceManager(pairingKeyStore: keyStore, userDefaults: defaults)

        XCTAssertTrue(fresh.devices.isEmpty)
        XCTAssertFalse(fresh.userIdleEnabled)
        XCTAssertFalse(fresh.speakers.isEnabled)
    }
}
