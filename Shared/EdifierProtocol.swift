//
//  EdifierProtocol.swift
//  LGTV Companion Shared
//
//  Frame building and parsing for the Bluetooth LE control protocol of
//  Edifier M90 speakers (the one the EDIFIER ConneX phone app speaks).
//  Pure data handling, no Bluetooth in here, so it stays unit-testable.
//
//  Protocol facts come from the community reference
//  https://github.com/kralonur/edifier-speakers-ble (MIT, docs/edifier-m90-ble.md)
//  and were confirmed read-only against an M90 with firmware 1.5.1.
//
//  Frame layout:
//    AA <app> <opcode> <length hi> <length lo> <payload…> <checksum>   request
//    BB <app> <opcode> <length hi> <length lo> <payload…> <checksum>   reply
//  The checksum is the low byte of the sum of all preceding bytes.
//

import Foundation

/// Level of the subwoofer output, as named in the ConneX app.
public enum EdifierSubOutLevel: UInt8, CaseIterable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2

    public var id: UInt8 { rawValue }

    public var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

public enum EdifierReply: Equatable {
    case volume(maximum: Int, current: Int)
    case subOut(EdifierSubOutLevel)
    case name(String)
    /// Any other valid frame (acknowledgements, settings we do not use).
    case other(app: UInt8, opcode: UInt8)
}

public enum EdifierProtocol {
    /// Bluetooth identifiers of the M90 control service.
    public static let advertisedServiceUUID = "4503"
    public static let serviceUUID = "48094503-1A48-11E9-AB14-D663BD873D93"
    public static let notifyCharacteristicUUID = "48090001-1A48-11E9-AB14-D663BD873D93"
    public static let writeCharacteristicUUID = "48090002-1A48-11E9-AB14-D663BD873D93"

    /// Volume range reported by the M90 (0...50). Used until the speaker
    /// states its own maximum.
    public static let defaultMaxVolume = 50

    private static let requestHeader: UInt8 = 0xAA
    private static let replyHeader: UInt8 = 0xBB
    private static let acknowledgeHeader: UInt8 = 0xCC

    private static let mainApp: UInt8 = 0xEC
    /// Sub Out lives under its own application code.
    private static let subOutApp: UInt8 = 0xED

    private static let opcodeQueryVolume: UInt8 = 0x66
    private static let opcodeSetVolume: UInt8 = 0x67
    private static let opcodeQueryName: UInt8 = 0xC9
    private static let opcodeQuerySubOut: UInt8 = 0x13
    private static let opcodeSetSubOut: UInt8 = 0x14
    /// The M90 has a single Sub Out, addressed as index 0.
    private static let subOutIndex: UInt8 = 0x00

    private static let headerLength = 5
    private static let checksumLength = 1

    // MARK: Requests

    public static func queryVolume() -> Data { frame(app: mainApp, opcode: opcodeQueryVolume) }
    public static func queryName() -> Data { frame(app: mainApp, opcode: opcodeQueryName) }
    public static func querySubOut() -> Data { frame(app: subOutApp, opcode: opcodeQuerySubOut) }

    /// Volume is clamped to 0...maximum; the speaker's byte range is 0...50.
    public static func setVolume(_ volume: Int, maximum: Int = defaultMaxVolume) -> Data {
        let clamped = UInt8(min(max(volume, 0), min(maximum, Int(UInt8.max))))
        return frame(app: mainApp, opcode: opcodeSetVolume, payload: [clamped])
    }

    public static func setSubOut(_ level: EdifierSubOutLevel) -> Data {
        frame(app: subOutApp, opcode: opcodeSetSubOut, payload: [subOutIndex, level.rawValue])
    }

    static func frame(app: UInt8, opcode: UInt8, payload: [UInt8] = []) -> Data {
        var bytes: [UInt8] = [requestHeader, app, opcode,
                              UInt8((payload.count >> 8) & 0xFF), UInt8(payload.count & 0xFF)]
        bytes += payload
        bytes.append(checksum(bytes))
        return Data(bytes)
    }

    static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(UInt8(0)) { $0 &+ $1 }
    }

    // MARK: Replies

    /// Parses every complete, checksum-valid frame in `data`. One Bluetooth
    /// notification normally holds exactly one frame; anything malformed
    /// ends parsing rather than being guessed at.
    public static func parse(_ data: Data) -> [EdifierReply] {
        let bytes = [UInt8](data)
        var replies: [EdifierReply] = []
        var offset = 0

        while offset + headerLength + checksumLength <= bytes.count {
            let header = bytes[offset]
            guard header == replyHeader || header == acknowledgeHeader else { break }

            let payloadLength = Int(bytes[offset + 3]) << 8 | Int(bytes[offset + 4])
            let frameEnd = offset + headerLength + payloadLength + checksumLength
            guard frameEnd <= bytes.count else { break }

            let body = bytes[offset..<(frameEnd - checksumLength)]
            guard checksum(body) == bytes[frameEnd - checksumLength] else { break }

            let payload = Array(bytes[(offset + headerLength)..<(frameEnd - checksumLength)])
            replies.append(decode(header: header, app: bytes[offset + 1], opcode: bytes[offset + 2], payload: payload))
            offset = frameEnd
        }
        return replies
    }

    private static func decode(header: UInt8, app: UInt8, opcode: UInt8, payload: [UInt8]) -> EdifierReply {
        // Only query answers carry state. A setter's acknowledgement reuses
        // the setter's opcode, so matching on the query opcodes is enough.
        guard header == replyHeader else { return .other(app: app, opcode: opcode) }

        switch (app, opcode) {
        case (mainApp, opcodeQueryVolume) where payload.count == 2:
            return .volume(maximum: Int(payload[0]), current: Int(payload[1]))
        case (subOutApp, opcodeQuerySubOut) where payload.count == 2:
            if let level = EdifierSubOutLevel(rawValue: payload[1]) { return .subOut(level) }
            return .other(app: app, opcode: opcode)
        case (mainApp, opcodeQueryName):
            return .name(String(decoding: payload, as: UTF8.self))
        default:
            return .other(app: app, opcode: opcode)
        }
    }
}
