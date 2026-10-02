//
//  PairingKeyStore.swift
//  LGTV Companion Shared
//
//  Keeps the TV pairing keys in the macOS keychain instead of in the app's
//  preferences file.
//
//  A pairing key lets anyone who has it control the TV. The preferences file
//  is plain text, readable by every process of the user and included in
//  backups. The keychain encrypts the key and ties access to this app's code
//  signature.
//

import Foundation
import Security

public protocol PairingKeyStoring {
    /// Stores the key. Returns true only if it can be read back afterwards.
    func save(_ key: String, for deviceID: UUID) -> Bool
    func load(for deviceID: UUID) -> String?
    func delete(for deviceID: UUID)
}

public struct KeychainPairingKeyStore: PairingKeyStoring {
    private static let defaultService = "com.lgtvcompanion.mac.pairing-key"
    private static let itemLabel = "LGTV Companion pairing key"

    private let service: String

    public init(service: String? = nil) {
        self.service = service ?? Self.defaultService
    }

    public func save(_ key: String, for deviceID: UUID) -> Bool {
        let data = Data(key.utf8)
        var status = SecItemUpdate(query(for: deviceID) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(for: deviceID)
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = Self.itemLabel
            status = SecItemAdd(item as CFDictionary, nil)
        }
        // Reading back proves the key is really retrievable. The caller
        // deletes its plain-text copy based on this answer.
        return status == errSecSuccess && load(for: deviceID) == key
    }

    public func load(for deviceID: UUID) -> String? {
        var request = query(for: deviceID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(for deviceID: UUID) {
        SecItemDelete(query(for: deviceID) as CFDictionary)
    }

    private func query(for deviceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID.uuidString
        ]
    }
}

/// Reads and writes the device list, keeping pairing keys out of it.
enum DevicePersistence {

    /// Encodes the devices for the preferences file. Every pairing key that
    /// the key store accepted is left out. A key the store could NOT take
    /// stays in the file: losing the pairing would be worse than keeping the
    /// old, weaker storage for that one device.
    static func encode(_ devices: [WebOSDevice], keyStore: PairingKeyStoring) -> Data? {
        let withoutStoredKeys = devices.map { device -> WebOSDevice in
            guard let key = device.pairingKey, keyStore.save(key, for: device.id) else {
                return device
            }
            var copy = device
            copy.pairingKey = nil
            return copy
        }
        return try? JSONEncoder().encode(withoutStoredKeys)
    }

    /// Decodes the device list and fills in the pairing keys from the key
    /// store. `needsResave` is true if the file still contained a key in
    /// plain text (written by an older version, or kept after a failed
    /// store): saving again moves it.
    static func decode(_ data: Data, keyStore: PairingKeyStoring) -> (devices: [WebOSDevice], needsResave: Bool)? {
        guard var devices = try? JSONDecoder().decode([WebOSDevice].self, from: data) else {
            return nil
        }

        var needsResave = false
        for index in devices.indices {
            if devices[index].pairingKey != nil {
                needsResave = true
            } else {
                devices[index].pairingKey = keyStore.load(for: devices[index].id)
            }
        }
        return (devices, needsResave)
    }
}
