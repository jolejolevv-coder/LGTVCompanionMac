//
//  SpeakerAutomation.swift
//  LGTV Companion Shared
//
//  Everything the app decides about the speakers on top of plain remote
//  control: which sound is selected, the user's own EQ curve, night mode
//  with its schedule, and switching the input when the Mac wakes.
//
//  EdifierSpeakerController only transports commands. This class holds the
//  settings and reacts to what the speakers report. Main thread only.
//

import Foundation

public final class SpeakerAutomation: ObservableObject {
    /// The user's own curve for the speakers' Custom slot.
    @Published public private(set) var myEQ: [Double]

    @Published public private(set) var nightModeActive: Bool
    @Published public private(set) var nightScheduleEnabled: Bool
    @Published public private(set) var nightSchedule: NightSchedule
    @Published public private(set) var nightVolumeLimit: Int
    @Published public private(set) var nightSubOut: EdifierSubOutLevel

    @Published public private(set) var wakeInputEnabled: Bool
    @Published public private(set) var wakeInput: EdifierInput

    private static let defaultNightStart = 22 * 60
    private static let defaultNightEnd = 7 * 60
    /// Of the speakers' 0...50.
    private static let defaultNightVolumeLimit = 15
    private static let scheduleCheckSeconds: TimeInterval = 30
    /// Bluetooth is not ready the instant the Mac wakes.
    private static let wakeDelaySeconds: TimeInterval = 3

    private enum Key {
        static let myEQ = "lgtvcompanion.speakers.myEQ"
        static let nightActive = "lgtvcompanion.speakers.nightActive"
        static let nightScheduleEnabled = "lgtvcompanion.speakers.nightScheduleEnabled"
        static let nightStart = "lgtvcompanion.speakers.nightStart"
        static let nightEnd = "lgtvcompanion.speakers.nightEnd"
        static let nightVolumeLimit = "lgtvcompanion.speakers.nightVolumeLimit"
        static let nightSubOut = "lgtvcompanion.speakers.nightSubOut"
        static let subOutBeforeNight = "lgtvcompanion.speakers.subOutBeforeNight"
        static let wakeInputEnabled = "lgtvcompanion.speakers.wakeInputEnabled"
        static let wakeInput = "lgtvcompanion.speakers.wakeInput"
    }

    private let speakers: EdifierSpeakerController
    private let defaults: UserDefaults

    /// Sub Out level to return to when night mode ends.
    private var subOutBeforeNight: EdifierSubOutLevel?
    /// Night mode sets the Sub Out once per activation. After that the user
    /// may change it by hand without the app forcing it back.
    private var nightSubOutApplied = false
    /// Night mode ended while the speakers were unreachable: restore the
    /// Sub Out at the next contact.
    private var restoreSubOutPending = false
    private var wakeInputPending = false

    private var scheduleTimer: Timer?
    private var lastScheduleVerdict: Bool?

    public init(speakers: EdifierSpeakerController, defaults: UserDefaults = .standard) {
        self.speakers = speakers
        self.defaults = defaults

        let bandCount = EdifierProtocol.eqBandFrequencies.count
        if let stored = defaults.array(forKey: Key.myEQ) as? [Double], stored.count == bandCount {
            myEQ = stored.map(EdifierProtocol.snappedGain)
        } else {
            myEQ = SpeakerSoundLibrary.flatGains
        }

        nightModeActive = defaults.bool(forKey: Key.nightActive)
        nightScheduleEnabled = defaults.bool(forKey: Key.nightScheduleEnabled)
        nightSchedule = NightSchedule(
            startMinutes: defaults.object(forKey: Key.nightStart) as? Int ?? Self.defaultNightStart,
            endMinutes: defaults.object(forKey: Key.nightEnd) as? Int ?? Self.defaultNightEnd
        )
        nightVolumeLimit = defaults.object(forKey: Key.nightVolumeLimit) as? Int ?? Self.defaultNightVolumeLimit
        nightSubOut = (defaults.object(forKey: Key.nightSubOut) as? Int)
            .flatMap { EdifierSubOutLevel(rawValue: UInt8(clamping: $0)) } ?? .low
        subOutBeforeNight = (defaults.object(forKey: Key.subOutBeforeNight) as? Int)
            .flatMap { EdifierSubOutLevel(rawValue: UInt8(clamping: $0)) }

        wakeInputEnabled = defaults.bool(forKey: Key.wakeInputEnabled)
        wakeInput = (defaults.object(forKey: Key.wakeInput) as? Int)
            .flatMap { EdifierInput(rawValue: UInt8(clamping: $0)) } ?? .optical

        if nightModeActive {
            speakers.setVolumeLimit(nightVolumeLimit)
        }

        let timer = Timer(timeInterval: Self.scheduleCheckSeconds, repeats: true) { [weak self] _ in
            self?.checkSchedule()
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduleTimer = timer
        checkSchedule()
    }

    deinit {
        scheduleTimer?.invalidate()
    }

    // MARK: - Sound

    /// The sound the speakers are playing, nil until they reported it.
    public var currentSound: SpeakerSound? {
        guard let preset = speakers.eqPreset else { return nil }
        return SpeakerSoundLibrary.identify(preset: preset, customEQ: speakers.customEQ)
    }

    public func selectSound(_ sound: SpeakerSound) {
        switch sound {
        case .preset(let preset):
            speakers.setEQPreset(preset)
        case .curve:
            guard let gains = SpeakerSoundLibrary.gains(for: sound, myEQ: myEQ) else { return }
            speakers.applyEQCurve(gains)
        }
    }

    /// Changes one band of My EQ. If another sound is selected, My EQ takes
    /// over, since editing a curve nobody hears would be pointless.
    public func setMyEQBand(index: Int, gainDB: Double) {
        guard myEQ.indices.contains(index) else { return }
        let gain = EdifierProtocol.snappedGain(gainDB)
        guard myEQ[index] != gain || currentSound != .curve(SpeakerSoundLibrary.myEQID) else { return }

        myEQ[index] = gain
        defaults.set(myEQ, forKey: Key.myEQ)

        if currentSound == .curve(SpeakerSoundLibrary.myEQID), speakers.customEQ != nil {
            speakers.setEQBand(index: index, gainDB: gain)
        } else {
            speakers.applyEQCurve(myEQ)
        }
    }

    public func resetMyEQ() {
        myEQ = SpeakerSoundLibrary.flatGains
        defaults.set(myEQ, forKey: Key.myEQ)
        speakers.applyEQCurve(myEQ)
    }

    // MARK: - Night mode

    public func setNightMode(_ active: Bool) {
        guard active != nightModeActive else { return }
        nightModeActive = active
        defaults.set(active, forKey: Key.nightActive)

        if active {
            nightSubOutApplied = false
            restoreSubOutPending = false
            speakers.setVolumeLimit(nightVolumeLimit)
        } else {
            speakers.setVolumeLimit(nil)
            restoreSubOutPending = subOutBeforeNight != nil
        }
        // Applies at once if the speakers are connected; otherwise connect,
        // and the rest happens when they report their state.
        syncNightSubOut()
        speakers.refresh()
    }

    public func setNightSchedule(enabled: Bool) {
        nightScheduleEnabled = enabled
        defaults.set(enabled, forKey: Key.nightScheduleEnabled)
        lastScheduleVerdict = nil
        checkSchedule()
    }

    public func setNightSchedule(startMinutes: Int, endMinutes: Int) {
        nightSchedule = NightSchedule(startMinutes: startMinutes, endMinutes: endMinutes)
        defaults.set(startMinutes, forKey: Key.nightStart)
        defaults.set(endMinutes, forKey: Key.nightEnd)
        lastScheduleVerdict = nil
        checkSchedule()
    }

    public func setNightVolumeLimit(_ limit: Int) {
        nightVolumeLimit = min(max(limit, 1), speakers.maxVolume)
        defaults.set(nightVolumeLimit, forKey: Key.nightVolumeLimit)
        if nightModeActive {
            speakers.setVolumeLimit(nightVolumeLimit)
        }
    }

    public func setNightSubOut(_ level: EdifierSubOutLevel) {
        nightSubOut = level
        defaults.set(Int(level.rawValue), forKey: Key.nightSubOut)
        if nightModeActive {
            nightSubOutApplied = false
            syncNightSubOut()
        }
    }

    /// Follows the schedule on its edges only: entering the window turns
    /// night mode on, leaving it turns it off. In between, a manual toggle
    /// stays as the user set it.
    private func checkSchedule() {
        guard nightScheduleEnabled, speakers.isEnabled else {
            lastScheduleVerdict = nil
            return
        }
        let isNight = nightSchedule.contains(minutesOfDay: NightSchedule.minutesOfDay(for: Date()))
        defer { lastScheduleVerdict = isNight }

        if let last = lastScheduleVerdict {
            if isNight != last { setNightMode(isNight) }
        } else if isNight {
            // First check (launch, or schedule just changed) inside the window.
            setNightMode(true)
        }
    }

    private func syncNightSubOut() {
        guard let current = speakers.subOut else { return }

        if nightModeActive {
            guard !nightSubOutApplied else { return }
            nightSubOutApplied = true
            if subOutBeforeNight == nil {
                subOutBeforeNight = current
                defaults.set(Int(current.rawValue), forKey: Key.subOutBeforeNight)
            }
            if current != nightSubOut {
                speakers.setSubOut(nightSubOut)
            }
        } else if restoreSubOutPending, let previous = subOutBeforeNight {
            restoreSubOutPending = false
            subOutBeforeNight = nil
            defaults.removeObject(forKey: Key.subOutBeforeNight)
            if current != previous {
                speakers.setSubOut(previous)
            }
        }
    }

    // MARK: - Wake

    public func setWakeInput(enabled: Bool) {
        wakeInputEnabled = enabled
        defaults.set(enabled, forKey: Key.wakeInputEnabled)
    }

    public func setWakeInput(_ input: EdifierInput) {
        wakeInput = input
        defaults.set(Int(input.rawValue), forKey: Key.wakeInput)
    }

    /// Makes sure the speakers listen to the configured input after the Mac
    /// woke up, whatever they were switched to in the meantime.
    public func macDidWake() {
        guard speakers.isEnabled, wakeInputEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeDelaySeconds) { [weak self] in
            guard let self = self else { return }
            self.wakeInputPending = true
            self.speakers.refresh()
        }
    }

    // MARK: - Reports from the speakers

    public func speakersReported(_ reply: EdifierReply) {
        switch reply {
        case .volume(_, let current):
            if nightModeActive, current > nightVolumeLimit {
                speakers.setVolume(nightVolumeLimit)
            }
        case .subOut:
            syncNightSubOut()
        case .input(let reported):
            // Acts on the freshly reported input only, never on a cached one.
            guard wakeInputPending else { return }
            wakeInputPending = false
            if reported != wakeInput {
                speakers.setInput(wakeInput)
            }
        case .customEQ(let gains):
            adoptCustomCurve(gains)
        case .eqPreset, .name, .other:
            break
        }
    }

    /// A Custom curve that is none of the app's own is the user's (set in
    /// the phone app, or already there before this app): keep it as My EQ so
    /// selecting Techno or Hip-Hop never destroys it.
    private func adoptCustomCurve(_ gains: [Double]) {
        // While a curve is being written band by band, a read shows a mix of
        // old and new. That mix must not become My EQ.
        guard !speakers.hasPendingWrites, speakers.eqPreset == .custom, gains != myEQ,
              SpeakerSoundLibrary.identify(preset: .custom, customEQ: gains) == .curve(SpeakerSoundLibrary.myEQID)
        else { return }
        myEQ = gains
        defaults.set(gains, forKey: Key.myEQ)
    }
}
