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
public enum EdifierSubOutLevel: UInt8, CaseIterable, Identifiable, Hashable {
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

/// Physical input of the speakers.
public enum EdifierInput: UInt8, CaseIterable, Identifiable, Hashable {
    case bluetooth = 1
    case usb = 2
    case hdmi = 3
    case optical = 4
    case aux = 5

    public var id: UInt8 { rawValue }

    public var label: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .usb: return "USB"
        case .hdmi: return "HDMI"
        case .optical: return "Optical"
        case .aux: return "AUX"
        }
    }

    /// Fits five options into one row of the menu.
    public var shortLabel: String {
        switch self {
        case .bluetooth: return "BT"
        case .optical: return "OPT"
        default: return label
        }
    }
}

/// Sound presets built into the speakers. `custom` is the one slot whose
/// nine bands can be set freely.
public enum EdifierEQPreset: UInt8, CaseIterable, Identifiable, Hashable {
    case classic = 0
    case monitor = 1
    case dynamic = 2
    case custom = 3

    public var id: UInt8 { rawValue }

    public var label: String {
        switch self {
        case .classic: return "Classic"
        case .monitor: return "Monitor"
        case .dynamic: return "Dynamic"
        case .custom: return "Custom"
        }
    }
}

public enum EdifierReply: Equatable {
    case volume(maximum: Int, current: Int)
    case subOut(EdifierSubOutLevel)
    case name(String)
    case input(EdifierInput)
    case eqPreset(EdifierEQPreset)
    /// Gain of each custom EQ band in dB, in the order of `eqBandFrequencies`.
    case customEQ([Double])
    /// Whether the speakers go to standby by themselves after a while
    /// without sound.
    case powerSave(Bool)
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

    /// Center frequencies (Hz) of the M90's nine custom EQ bands.
    public static let eqBandFrequencies = [62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    /// The speaker accepts -3...+3 dB per band, in steps of 0.5 dB.
    public static let eqGainRange: ClosedRange<Double> = -3...3
    public static let eqGainStep = 0.5
    /// Byte value that means 0 dB; each step of 1 is 0.5 dB.
    private static let eqZeroGainCode = 6
    private static let eqFormat: UInt8 = 0x10
    private static let eqRecordLength = 4

    private static let requestHeader: UInt8 = 0xAA
    private static let replyHeader: UInt8 = 0xBB
    private static let acknowledgeHeader: UInt8 = 0xCC

    private static let mainApp: UInt8 = 0xEC
    /// Sub Out lives under its own application code.
    private static let subOutApp: UInt8 = 0xED

    private static let opcodeQueryVolume: UInt8 = 0x66
    private static let opcodeSetVolume: UInt8 = 0x67
    private static let opcodeQueryName: UInt8 = 0xC9
    private static let opcodeQueryInput: UInt8 = 0x61
    private static let opcodeSetInput: UInt8 = 0x62
    /// The M90's inputs form group 1D (the M60 uses another group).
    private static let inputGroup: UInt8 = 0x1D
    private static let opcodeQueryEQPreset: UInt8 = 0xD5
    private static let opcodeSetEQPreset: UInt8 = 0xC4
    private static let opcodeQueryCustomEQ: UInt8 = 0x43
    private static let opcodeSetEQBand: UInt8 = 0x44
    private static let opcodeQueryPowerSave: UInt8 = 0xB1
    private static let opcodeSetPowerSave: UInt8 = 0xB2
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

    public static func queryInput() -> Data { frame(app: mainApp, opcode: opcodeQueryInput) }

    public static func setInput(_ input: EdifierInput) -> Data {
        frame(app: mainApp, opcode: opcodeSetInput, payload: [inputGroup, input.rawValue])
    }

    public static func queryEQPreset() -> Data { frame(app: mainApp, opcode: opcodeQueryEQPreset) }

    public static func setEQPreset(_ preset: EdifierEQPreset) -> Data {
        frame(app: mainApp, opcode: opcodeSetEQPreset, payload: [preset.rawValue])
    }

    public static func queryCustomEQ() -> Data { frame(app: mainApp, opcode: opcodeQueryCustomEQ) }

    public static func queryPowerSave() -> Data { frame(app: mainApp, opcode: opcodeQueryPowerSave) }

    public static func setPowerSave(_ enabled: Bool) -> Data {
        frame(app: mainApp, opcode: opcodeSetPowerSave, payload: [enabled ? 1 : 0])
    }

    /// Sets one band of the custom EQ. Only takes effect while the Custom
    /// preset is selected. nil for a band index that does not exist.
    public static func setEQBand(index: Int, gainDB: Double) -> Data? {
        guard eqBandFrequencies.indices.contains(index) else { return nil }
        let frequency = eqBandFrequencies[index]
        return frame(app: mainApp, opcode: opcodeSetEQBand,
                     payload: [UInt8(index), UInt8(frequency >> 8), UInt8(frequency & 0xFF), gainCode(for: gainDB)])
    }

    /// Clamps to the allowed range and snaps to the 0.5 dB grid.
    public static func snappedGain(_ gainDB: Double) -> Double {
        let clamped = min(max(gainDB, eqGainRange.lowerBound), eqGainRange.upperBound)
        return (clamped / eqGainStep).rounded() * eqGainStep
    }

    static func gainCode(for gainDB: Double) -> UInt8 {
        UInt8(Int((snappedGain(gainDB) / eqGainStep).rounded()) + eqZeroGainCode)
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

    /// Layout: <format 10> <band count 09> <nine records of
    /// index, frequency hi, frequency lo, gain> <date> [<name>].
    /// Every record is checked against the expected index and frequency, so
    /// a different layout (other model, other firmware) is rejected instead
    /// of being read as nonsense gains.
    private static func decodeCustomEQ(_ payload: [UInt8]) -> [Double]? {
        let bandCount = eqBandFrequencies.count
        guard payload.count >= 2 + bandCount * eqRecordLength,
              payload[0] == eqFormat, Int(payload[1]) == bandCount else { return nil }

        var gains: [Double] = []
        for index in 0..<bandCount {
            let offset = 2 + index * eqRecordLength
            let frequency = Int(payload[offset + 1]) << 8 | Int(payload[offset + 2])
            guard Int(payload[offset]) == index, frequency == eqBandFrequencies[index] else { return nil }
            gains.append(Double(Int(payload[offset + 3]) - eqZeroGainCode) * eqGainStep)
        }
        return gains
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
        case (mainApp, opcodeQueryInput) where payload.count == 2 && payload[0] == inputGroup:
            if let input = EdifierInput(rawValue: payload[1]) { return .input(input) }
            return .other(app: app, opcode: opcode)
        case (mainApp, opcodeQueryEQPreset) where payload.count == 1:
            if let preset = EdifierEQPreset(rawValue: payload[0]) { return .eqPreset(preset) }
            return .other(app: app, opcode: opcode)
        case (mainApp, opcodeQueryPowerSave) where payload.count == 1 && payload[0] <= 1:
            return .powerSave(payload[0] == 1)
        case (mainApp, opcodeQueryCustomEQ):
            if let gains = decodeCustomEQ(payload) { return .customEQ(gains) }
            return .other(app: app, opcode: opcode)
        default:
            return .other(app: app, opcode: opcode)
        }
    }
}
