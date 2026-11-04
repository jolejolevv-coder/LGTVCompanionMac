import XCTest
@testable import LGTVCompanionShared

final class AutoOffPolicyTests: XCTestCase {

    private struct Row {
        let name: String
        let macDrivesLGTV: Bool
        let input: TVInputState
        let expected: Bool
    }

    private let rows: [Row] = [
        // Mac on the TV: only a different input blocks the power off.
        Row(name: "Mac on TV, TV shows Mac", macDrivesLGTV: true, input: .mac, expected: true),
        Row(name: "Mac on TV, TV shows console", macDrivesLGTV: true, input: .other, expected: false),
        Row(name: "Mac on TV, input unreadable", macDrivesLGTV: true, input: .unknown, expected: true),
        Row(name: "Mac on TV, no input configured", macDrivesLGTV: true, input: .notConfigured, expected: true),
        // Cable unplugged or Mac on another monitor: never turn the TV off.
        Row(name: "no LG TV, TV shows Mac port", macDrivesLGTV: false, input: .mac, expected: false),
        Row(name: "no LG TV, TV shows console", macDrivesLGTV: false, input: .other, expected: false),
        Row(name: "no LG TV, input unreadable", macDrivesLGTV: false, input: .unknown, expected: false),
        Row(name: "no LG TV, no input configured", macDrivesLGTV: false, input: .notConfigured, expected: false),
    ]

    func testDecisionTable() {
        for row in rows {
            XCTAssertEqual(AutoOffPolicy.mayPowerOff(macDrivesLGTV: row.macDrivesLGTV, input: row.input),
                           row.expected, row.name)
        }
    }
}

final class LGDisplayDetectorTests: XCTestCase {

    private static let lenovoVendor: UInt32 = 0x30AE

    func testLGVendorMatchesWithoutName() {
        XCTAssertTrue(LGDisplayDetector.isLGTV(vendorNumber: LGDisplayDetector.lgVendorNumber, name: nil))
    }

    func testNameFallbackMatches() {
        XCTAssertTrue(LGDisplayDetector.isLGTV(vendorNumber: 0, name: "LG TV SSCR2"))
        XCTAssertTrue(LGDisplayDetector.isLGTV(vendorNumber: 0, name: "lg tv"))
    }

    func testOtherMonitorDoesNotMatch() {
        XCTAssertFalse(LGDisplayDetector.isLGTV(vendorNumber: Self.lenovoVendor, name: "LEN T24i-2L"))
        XCTAssertFalse(LGDisplayDetector.isLGTV(vendorNumber: Self.lenovoVendor, name: nil))
    }
}

/// In-memory stand-in for the keychain.
private final class AutoOffKeyStore: PairingKeyStoring {
    var keys: [UUID: String] = [:]
    func save(_ key: String, for deviceID: UUID) -> Bool { keys[deviceID] = key; return true }
    func load(for deviceID: UUID) -> String? { keys[deviceID] }
    func delete(for deviceID: UUID) { keys[deviceID] = nil }
}

/// The filter in front of every automatic power off. The devices carry no
/// Mac input, so no case reaches the network.
@MainActor
final class AutoOffFilterTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "lgtvcompanion.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeManager(macDrivesLGTV: Bool) -> (DeviceManager, WebOSDevice) {
        let manager = DeviceManager(pairingKeyStore: AutoOffKeyStore(), userDefaults: defaults)
        manager.macDrivesLGTVDisplay = { macDrivesLGTV }
        let device = WebOSDevice(name: "TV", ipAddress: "192.0.2.10", macAddress: "80:5B:65:D6:27:E0")
        return (manager, device)
    }

    func testNothingIsTurnedOffWithoutLGTVDisplay() async {
        let (manager, device) = makeManager(macDrivesLGTV: false)
        let allowed = await manager.devicesAllowedToAutoOff([device])
        XCTAssertEqual(allowed, [])
    }

    func testTVIsTurnedOffWhenMacDrivesIt() async {
        let (manager, device) = makeManager(macDrivesLGTV: true)
        let allowed = await manager.devicesAllowedToAutoOff([device])
        XCTAssertEqual(allowed, [device])
    }
}
