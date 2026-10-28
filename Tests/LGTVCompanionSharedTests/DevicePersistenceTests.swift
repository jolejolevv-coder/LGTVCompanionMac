import XCTest
@testable import LGTVCompanionShared

/// In-memory stand-in for the keychain.
private final class FakeKeyStore: PairingKeyStoring {
    var keys: [UUID: String] = [:]
    var acceptsWrites = true
    private(set) var saveCalls = 0
    private(set) var loadCalls = 0

    func save(_ key: String, for deviceID: UUID) -> Bool {
        saveCalls += 1
        guard acceptsWrites else { return false }
        keys[deviceID] = key
        return true
    }
    func load(for deviceID: UUID) -> String? {
        loadCalls += 1
        return keys[deviceID]
    }
    func delete(for deviceID: UUID) { keys[deviceID] = nil }
}

final class DevicePersistenceTests: XCTestCase {

    private func device(key: String?) -> WebOSDevice {
        WebOSDevice(name: "TV", ipAddress: "192.168.178.25", macAddress: "80:5B:65:D6:27:E0", pairingKey: key)
    }

    private func text(_ data: Data?) -> String {
        String(decoding: data ?? Data(), as: UTF8.self)
    }

    func testEncodingMovesTheKeyIntoTheStoreAndOutOfTheFile() {
        let store = FakeKeyStore()
        let tv = device(key: "secret-key-123")

        let data = DevicePersistence.encode([tv], keyStore: store)

        XCTAssertEqual(store.keys[tv.id], "secret-key-123")
        XCTAssertFalse(text(data).contains("secret-key-123"), "the key must not be written to the file")
        XCTAssertFalse(text(data).contains("pairingKey"))
    }

    func testKeyStaysInTheFileWhenTheStoreRefusesIt() {
        let store = FakeKeyStore()
        store.acceptsWrites = false

        let data = DevicePersistence.encode([device(key: "secret-key-123")], keyStore: store)

        XCTAssertTrue(text(data).contains("secret-key-123"), "a failed store must not lose the pairing")
    }

    func testRoundTripRestoresTheKeyFromTheStore() throws {
        let store = FakeKeyStore()
        let tv = device(key: "secret-key-123")
        let data = try XCTUnwrap(DevicePersistence.encode([tv], keyStore: store))

        let loaded = try XCTUnwrap(DevicePersistence.decode(data, keyStore: store))

        XCTAssertEqual(loaded.devices, [tv])
        XCTAssertFalse(loaded.needsResave)
    }

    func testLegacyFileWithPlainTextKeyIsFlaggedForMigration() throws {
        let tv = device(key: "legacy-key")
        let legacyFile = try JSONEncoder().encode([tv])   // what older versions wrote
        let store = FakeKeyStore()

        let loaded = try XCTUnwrap(DevicePersistence.decode(legacyFile, keyStore: store))

        XCTAssertEqual(loaded.devices.first?.pairingKey, "legacy-key")
        XCTAssertTrue(loaded.needsResave)

        // Saving once completes the move.
        let migrated = DevicePersistence.encode(loaded.devices, keyStore: store)
        XCTAssertEqual(store.keys[tv.id], "legacy-key")
        XCTAssertFalse(text(migrated).contains("legacy-key"))
    }

    func testUnpairedDeviceStaysUnpairedAndTouchesNothing() throws {
        let store = FakeKeyStore()
        let tv = device(key: nil)
        let data = try XCTUnwrap(DevicePersistence.encode([tv], keyStore: store))

        let loaded = try XCTUnwrap(DevicePersistence.decode(data, keyStore: store))

        XCTAssertNil(loaded.devices.first?.pairingKey)
        XCTAssertTrue(store.keys.isEmpty)
        XCTAssertFalse(loaded.needsResave)
    }

    func testKeysOfSeveralDevicesAreNotMixedUp() throws {
        let store = FakeKeyStore()
        let first = device(key: "key-one")
        let second = device(key: "key-two")
        let data = try XCTUnwrap(DevicePersistence.encode([first, second], keyStore: store))

        let loaded = try XCTUnwrap(DevicePersistence.decode(data, keyStore: store))

        XCTAssertEqual(loaded.devices.map(\.pairingKey), ["key-one", "key-two"])
    }

    func testCorruptFileYieldsNilInsteadOfAnEmptyList() {
        XCTAssertNil(DevicePersistence.decode(Data("not json".utf8), keyStore: FakeKeyStore()))
    }
}

final class CachingPairingKeyStoreTests: XCTestCase {

    func testSavingTheSameKeyAgainDoesNotTouchTheStore() {
        let inner = FakeKeyStore()
        let store = CachingPairingKeyStore(inner)
        let id = UUID()

        XCTAssertTrue(store.save("key-1", for: id))
        XCTAssertTrue(store.save("key-1", for: id))

        XCTAssertEqual(inner.saveCalls, 1)
    }

    func testAChangedKeyIsWritten() {
        let inner = FakeKeyStore()
        let store = CachingPairingKeyStore(inner)
        let id = UUID()

        _ = store.save("key-1", for: id)
        _ = store.save("key-2", for: id)

        XCTAssertEqual(inner.saveCalls, 2)
        XCTAssertEqual(inner.keys[id], "key-2")
    }

    func testARefusedKeyIsNotRemembered() {
        let inner = FakeKeyStore()
        inner.acceptsWrites = false
        let store = CachingPairingKeyStore(inner)
        let id = UUID()

        XCTAssertFalse(store.save("key-1", for: id))
        inner.acceptsWrites = true

        XCTAssertTrue(store.save("key-1", for: id))
        XCTAssertEqual(inner.saveCalls, 2)
    }

    func testLoadedKeyCountsAsStoredAndDeleteForgetsIt() {
        let inner = FakeKeyStore()
        let id = UUID()
        inner.keys[id] = "key-1"
        let store = CachingPairingKeyStore(inner)

        XCTAssertEqual(store.load(for: id), "key-1")
        XCTAssertEqual(store.load(for: id), "key-1")
        XCTAssertEqual(inner.loadCalls, 1)
        XCTAssertTrue(store.save("key-1", for: id))
        XCTAssertEqual(inner.saveCalls, 0)

        store.delete(for: id)

        XCTAssertNil(store.load(for: id))
        XCTAssertTrue(store.save("key-1", for: id))
        XCTAssertEqual(inner.saveCalls, 1)
    }
}
