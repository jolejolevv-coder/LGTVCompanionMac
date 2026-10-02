//
//  SpeakerSound.swift
//  LGTV Companion Shared
//
//  Sound choices for the speakers and the night schedule. Pure logic, no
//  Bluetooth, so it stays unit-testable.
//

import Foundation

/// A named set of gains for the speakers' nine custom EQ bands, in dB.
public struct EQCurve: Identifiable, Equatable {
    public let id: String
    public let name: String
    public var gains: [Double]

    public init(id: String, name: String, gains: [Double]) {
        self.id = id
        self.name = name
        self.gains = gains
    }
}

/// What the user can pick as "sound": a preset built into the speakers, or a
/// curve the app writes into the speakers' Custom slot.
public enum SpeakerSound: Hashable, Identifiable {
    case preset(EdifierEQPreset)
    case curve(String)

    public var id: String {
        switch self {
        case .preset(let preset): return "preset:\(preset.rawValue)"
        case .curve(let curveID): return "curve:\(curveID)"
        }
    }
}

public enum SpeakerSoundLibrary {
    public static let myEQID = "my-eq"
    public static let technoID = "techno"
    public static let hipHopID = "hip-hop"

    /// Bands: 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz. Range ±3 dB.

    /// Techno: hard kick and sub bass, low mids pulled back so the kick stays
    /// dry, bright top for hi-hats and percussion.
    public static let techno = EQCurve(id: technoID, name: "Techno",
                                       gains: [3, 2, 0, -1, -0.5, 0, 1, 2, 2.5])

    /// Hip-Hop: deep, round low end including the upper bass, mids left
    /// almost flat so voices stay forward, gentle presence, soft top.
    public static let hipHop = EQCurve(id: hipHopID, name: "Hip-Hop",
                                       gains: [3, 2.5, 1, 0, -0.5, 0.5, 1, 1, 0.5])

    public static let flatGains = [Double](repeating: 0, count: EdifierProtocol.eqBandFrequencies.count)

    public static let builtInCurves = [techno, hipHop]

    /// Order shown in the UI.
    public static let menuOrder: [SpeakerSound] = [
        .preset(.classic), .preset(.monitor), .preset(.dynamic),
        .curve(technoID), .curve(hipHopID), .curve(myEQID)
    ]

    public static func name(of sound: SpeakerSound) -> String {
        switch sound {
        case .preset(let preset): return preset.label
        case .curve(myEQID): return "My EQ"
        case .curve(let curveID): return builtInCurves.first { $0.id == curveID }?.name ?? curveID
        }
    }

    /// Tells which sound the speakers are playing, from what they report.
    /// A Custom curve that matches none of the app's curves is the user's
    /// own (set here or in the phone app) and counts as My EQ.
    public static func identify(preset: EdifierEQPreset, customEQ: [Double]?) -> SpeakerSound {
        guard preset == .custom else { return .preset(preset) }
        if let customEQ = customEQ, let match = builtInCurves.first(where: { $0.gains == customEQ }) {
            return .curve(match.id)
        }
        return .curve(myEQID)
    }

    /// Gains to write for a curve choice. nil for presets (nothing to write)
    /// and unknown ids.
    public static func gains(for sound: SpeakerSound, myEQ: [Double]) -> [Double]? {
        switch sound {
        case .preset: return nil
        case .curve(myEQID): return myEQ
        case .curve(let curveID): return builtInCurves.first { $0.id == curveID }?.gains
        }
    }
}

/// Daily time window, possibly across midnight (22:00 to 07:00).
public struct NightSchedule: Equatable {
    public static let minutesPerDay = 24 * 60

    /// Minutes after midnight, 0...1439.
    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    /// The start is inside the window, the end is not. An empty window
    /// (start == end) never matches.
    public func contains(minutesOfDay: Int) -> Bool {
        if startMinutes == endMinutes { return false }
        if startMinutes < endMinutes {
            return minutesOfDay >= startMinutes && minutesOfDay < endMinutes
        }
        return minutesOfDay >= startMinutes || minutesOfDay < endMinutes
    }

    public static func minutesOfDay(for date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
