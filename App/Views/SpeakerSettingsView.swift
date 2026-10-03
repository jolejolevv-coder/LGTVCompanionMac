//
//  SpeakerSettingsView.swift
//  LGTV Companion
//
//  Settings tab for the Edifier speakers: connection, sound and equalizer,
//  night mode, behavior on wake.
//

import LGTVCompanionShared
import SwiftUI

struct SpeakerSettingsTab: View {
    @ObservedObject var speakers: EdifierSpeakerController
    @ObservedObject var automation: SpeakerAutomation

    var body: some View {
        Form {
            connectionSection
            if speakers.isEnabled {
                soundSection
                nightSection
                wakeSection
                powerSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            Toggle("Control Edifier speakers over Bluetooth", isOn: Binding(
                get: { speakers.isEnabled },
                set: { speakers.setEnabled($0) }
            ))
            .tint(.green)

            Text("For Edifier M90. The volume keys change the speakers' own volume. The speakers allow one Bluetooth client at a time, so the Edifier phone app cannot connect while this app is; the app disconnects after 20 seconds without use. If the speakers are unreachable, the keys fall back to the Mac volume.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if speakers.isEnabled {
                LabeledContent("Status") {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
                if speakers.hasKnownSpeaker {
                    Button("Forget Speakers") { speakers.forgetSpeaker() }
                }
            }
        } header: {
            Text("Speakers")
        }
    }

    private var statusText: String {
        let name = speakers.deviceName ?? "Edifier speakers"
        switch speakers.state {
        case .connected: return "\(name), connected"
        case .connecting: return "Searching…"
        case .unavailable: return "Not reachable"
        case .idle: return speakers.hasKnownSpeaker ? "\(name), standby" : "Not connected yet"
        }
    }

    // MARK: - Sound

    private var soundSection: some View {
        Section {
            Picker("Sound", selection: Binding(
                get: { automation.currentSound ?? .curve(SpeakerSoundLibrary.myEQID) },
                set: { automation.selectSound($0) }
            )) {
                ForEach(SpeakerSoundLibrary.menuOrder) { sound in
                    Text(SpeakerSoundLibrary.name(of: sound)).tag(sound)
                }
            }
            .disabled(speakers.eqPreset == nil)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("My EQ")
                    Spacer()
                    Button("Reset to Flat") { automation.resetMyEQ() }
                        .controlSize(.small)
                }

                EqualizerEditor(gains: automation.myEQ) { index, gain in
                    automation.setMyEQBand(index: index, gainDB: gain)
                }

                Text("Classic, Monitor and Dynamic are built into the speakers. Techno, Hip-Hop and My EQ are written into the speakers' Custom slot. Moving a slider switches to My EQ. Each band ranges from -3 to +3 dB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Sound")
        }
        .onAppear { speakers.refresh() }
    }

    // MARK: - Night mode

    private var nightSection: some View {
        Section {
            Toggle("Night mode", isOn: Binding(
                get: { automation.nightModeActive },
                set: { automation.setNightMode($0) }
            ))
            .tint(.indigo)

            Stepper(value: Binding(
                get: { automation.nightVolumeLimit },
                set: { automation.setNightVolumeLimit($0) }
            ), in: 1...speakers.maxVolume) {
                LabeledContent("Volume limit") {
                    Text("\(automation.nightVolumeLimit) of \(speakers.maxVolume)")
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Subwoofer", selection: Binding(
                get: { automation.nightSubOut },
                set: { automation.setNightSubOut($0) }
            )) {
                ForEach(EdifierSubOutLevel.allCases) { level in
                    Text(level.label).tag(level)
                }
            }

            Toggle("Turn on automatically", isOn: Binding(
                get: { automation.nightScheduleEnabled },
                set: { automation.setNightSchedule(enabled: $0) }
            ))
            .tint(.indigo)

            if automation.nightScheduleEnabled {
                DatePicker("From", selection: timeBinding(
                    minutes: automation.nightSchedule.startMinutes,
                    set: { automation.setNightSchedule(startMinutes: $0, endMinutes: automation.nightSchedule.endMinutes) }
                ), displayedComponents: .hourAndMinute)

                DatePicker("Until", selection: timeBinding(
                    minutes: automation.nightSchedule.endMinutes,
                    set: { automation.setNightSchedule(startMinutes: automation.nightSchedule.startMinutes, endMinutes: $0) }
                ), displayedComponents: .hourAndMinute)
            }

            Text("Night mode caps the volume and sets the subwoofer level. Turning it off removes the cap and restores the previous subwoofer level.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Night Mode")
        }
    }

    /// Bridges "minutes after midnight" to the Date a DatePicker edits.
    private func timeBinding(minutes: Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let startOfDay = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(byAdding: .minute, value: minutes, to: startOfDay) ?? startOfDay
            },
            set: { set(NightSchedule.minutesOfDay(for: $0)) }
        )
    }

    // MARK: - Power

    private var powerSection: some View {
        Section {
            Toggle("Power saving (auto standby)", isOn: Binding(
                get: { speakers.powerSaveEnabled ?? false },
                set: { speakers.setPowerSave($0) }
            ))
            .tint(.green)
            .disabled(speakers.powerSaveEnabled == nil)

            Text("On: the speakers go to standby by themselves after a while without sound, and then do not wake when the Mac does; they have to be switched on by hand. Off: they stay on and play at once, at the cost of idle power. The setting is stored in the speakers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Power")
        }
    }

    // MARK: - Wake

    private var wakeSection: some View {
        Section {
            Toggle("Switch the speakers' input when the Mac wakes", isOn: Binding(
                get: { automation.wakeInputEnabled },
                set: { automation.setWakeInput(enabled: $0) }
            ))
            .tint(.green)

            Picker("Input", selection: Binding(
                get: { automation.wakeInput },
                set: { automation.setWakeInput($0) }
            )) {
                ForEach(EdifierInput.allCases) { input in
                    Text(input.label).tag(input)
                }
            }
            .disabled(!automation.wakeInputEnabled)

            Text("Makes sure the Mac's sound comes out after waking, whatever the speakers were switched to in the meantime.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("When the Mac Wakes")
        }
    }
}

// MARK: - Equalizer

/// Nine vertical band sliders.
struct EqualizerEditor: View {
    let gains: [Double]
    let onChange: (Int, Double) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(EdifierProtocol.eqBandFrequencies.enumerated()), id: \.offset) { index, frequency in
                EqualizerBand(
                    gain: gains.indices.contains(index) ? gains[index] : 0,
                    label: Self.frequencyLabel(frequency),
                    onChange: { onChange(index, $0) }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 62 → "62", 1000 → "1k", 16000 → "16k".
    static func frequencyLabel(_ hertz: Int) -> String {
        hertz >= 1000 ? "\(hertz / 1000)k" : "\(hertz)"
    }
}

private struct EqualizerBand: View {
    let gain: Double
    let label: String
    let onChange: (Double) -> Void

    private static let trackHeight: CGFloat = 96
    private static let trackWidth: CGFloat = 4
    private static let thumbDiameter: CGFloat = 14

    private var range: ClosedRange<Double> { EdifierProtocol.eqGainRange }

    var body: some View {
        VStack(spacing: 4) {
            Text(Self.gainLabel(gain))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(gain == 0 ? Color.secondary : Color.primary)

            GeometryReader { geometry in
                let travel = geometry.size.height - Self.thumbDiameter
                let fraction = (gain - range.lowerBound) / (range.upperBound - range.lowerBound)
                let thumbY = travel * (1 - fraction)

                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: Self.trackWidth)
                        .frame(maxWidth: .infinity)
                    // 0 dB mark.
                    Rectangle()
                        .fill(Color.primary.opacity(0.3))
                        .frame(width: 12, height: 1)
                        .frame(maxWidth: .infinity)
                        .offset(y: geometry.size.height / 2)
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
                        .frame(maxWidth: .infinity)
                        .offset(y: thumbY)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        let position = min(max((drag.location.y - Self.thumbDiameter / 2) / max(travel, 1), 0), 1)
                        let raw = range.upperBound - Double(position) * (range.upperBound - range.lowerBound)
                        let snapped = EdifierProtocol.snappedGain(raw)
                        // Only report real steps, so a drag sends one command
                        // per half decibel instead of one per pixel.
                        if snapped != gain { onChange(snapped) }
                    }
                )
            }
            .frame(height: Self.trackHeight)

            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement()
        .accessibilityLabel("\(label) hertz")
        .accessibilityValue("\(Self.gainLabel(gain)) decibels")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? EdifierProtocol.eqGainStep : -EdifierProtocol.eqGainStep
            onChange(EdifierProtocol.snappedGain(gain + step))
        }
    }

    /// "+1.5", "0", "-3".
    static func gainLabel(_ gain: Double) -> String {
        if gain == 0 { return "0" }
        let text = gain == gain.rounded() ? String(Int(gain)) : String(format: "%.1f", gain)
        return gain > 0 ? "+\(text)" : text
    }
}
