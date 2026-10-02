//
//  SoftwareVolumeController.swift
//  LGTV Companion Shared
//
//  Attenuates the Mac's system audio before it leaves through HDMI.
//
//  HDMI outputs have no volume control in macOS, and a TV that forwards the
//  sound over optical cannot change the level either. So the level is changed
//  here: a Core Audio process tap captures all system audio and mutes the
//  original, an IOProc scales the samples and plays them on the same device.
//
//  The tap lives inside this process. If the app quits or crashes, macOS
//  removes it and the sound plays unattenuated again.
//

import Foundation
import CoreAudio
import AudioToolbox

public final class SoftwareVolumeController {
    /// Called on the main thread when the Mac's default output device changed.
    public var onOutputDeviceChanged: (() -> Void)?

    public private(set) var isRunning = false

    /// Time for a full-scale gain change. Long enough to avoid clicks, short
    /// enough to feel instant.
    private static let rampSeconds: Double = 0.02
    /// How long to keep the tap alive at full level before tearing it down,
    /// so the ramp back to 100 % can finish.
    private static let stopDelaySeconds: Double = 0.1

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.lgtvcompanion.softwarevolume", qos: .userInteractive)

    /// Gain the IOProc ramps towards. Written on the main thread, read on the
    /// audio thread. Raw storage instead of a lock: the audio thread must
    /// never block, and an aligned 32-bit load/store is atomic on arm64/x86.
    private let targetGain: UnsafeMutablePointer<Float32>
    /// Gain currently applied. Touched only by the audio thread.
    private let currentGain: UnsafeMutablePointer<Float32>

    private var outputListener: AudioObjectPropertyListenerBlock?
    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    public init() {
        targetGain = .allocate(capacity: 1)
        currentGain = .allocate(capacity: 1)
        targetGain.initialize(to: 1)
        currentGain.initialize(to: 1)

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onOutputDeviceChanged?()
        }
        outputListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &Self.defaultOutputAddress, .main, listener)
    }

    deinit {
        stop()
        if let listener = outputListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                                   &Self.defaultOutputAddress, .main, listener)
        }
        targetGain.deallocate()
        currentGain.deallocate()
    }

    // MARK: - Public API (main thread)

    /// True when the Mac's default output is an HDMI/DisplayPort device,
    /// i.e. sound goes to a display and macOS offers no volume control.
    public static func defaultOutputIsDigitalDisplay() -> Bool {
        guard let device = defaultOutputDevice(),
              let transport: UInt32 = property(device, kAudioDevicePropertyTransportType) else {
            return false
        }
        return transport == kAudioDeviceTransportTypeHDMI
            || transport == kAudioDeviceTransportTypeDisplayPort
    }

    /// Applies a gain in 0...1. Returns false if the tap could not be set up;
    /// the caller should then leave the volume keys to macOS.
    @discardableResult
    public func apply(gain: Float) -> Bool {
        targetGain.pointee = min(max(gain, 0), 1)

        if gain >= 1 {
            // Full level needs no tap. Let the ramp finish, then remove it so
            // 100 % costs neither latency nor CPU.
            guard isRunning else { return true }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopDelaySeconds) { [weak self] in
                guard let self = self, self.targetGain.pointee >= 1 else { return }
                self.stop()
            }
            return true
        }
        return isRunning || start()
    }

    public func stop() {
        if let ioProcID = ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        isRunning = false
    }

    // MARK: - Tap setup

    private func start() -> Bool {
        guard let outputDevice = Self.defaultOutputDevice(),
              let outputUID: CFString = Self.property(outputDevice, kAudioDevicePropertyDeviceUID) else {
            return false
        }

        // Exclude our own process: its playback is the attenuated signal and
        // must neither be captured again (feedback) nor muted.
        var excluded: [AudioObjectID] = []
        if let own = Self.ownProcessObject() { excluded = [own] }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true

        guard AudioHardwareCreateProcessTap(tapDescription, &tapID) == noErr else {
            stop()
            return false
        }

        // The IOProc multiplies Float32 samples. Any other tap format would
        // produce noise, so refuse to run instead.
        guard let format: AudioStreamBasicDescription = Self.property(tapID, kAudioTapPropertyFormat),
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              format.mSampleRate > 0 else {
            stop()
            return false
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LGTV Companion Software Volume",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString
            ]]
        ]
        guard AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID) == noErr else {
            stop()
            return false
        }

        // Start from unity so the first buffers ramp down instead of jumping.
        currentGain.pointee = 1
        let target = targetGain
        let current = currentGain
        let rampStep = Float32(1.0 / (format.mSampleRate * Self.rampSeconds))

        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) { _, inData, _, outData, _ in
            Self.render(input: inData, output: outData,
                        target: target.pointee, current: current, rampStep: rampStep)
        }
        guard status == noErr, let ioProcID = ioProcID,
              AudioDeviceStart(aggregateID, ioProcID) == noErr else {
            stop()
            return false
        }

        isRunning = true
        return true
    }

    /// Audio thread. Copies input to output scaled by a gain that moves
    /// towards `target` by `rampStep` per frame. No allocation, no locks.
    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>,
                               target: Float32,
                               current: UnsafeMutablePointer<Float32>,
                               rampStep: Float32) {
        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
        let startGain = current.pointee
        var endGain = startGain

        for index in 0..<outputBuffers.count {
            let out = outputBuffers[index]
            guard let destination = out.mData?.assumingMemoryBound(to: Float32.self) else { continue }
            let destinationCount = Int(out.mDataByteSize) / MemoryLayout<Float32>.size

            guard index < inputBuffers.count,
                  let source = inputBuffers[index].mData?.assumingMemoryBound(to: Float32.self) else {
                for n in 0..<destinationCount { destination[n] = 0 }
                continue
            }

            let sourceCount = Int(inputBuffers[index].mDataByteSize) / MemoryLayout<Float32>.size
            let count = min(sourceCount, destinationCount)
            let channels = max(Int(out.mNumberChannels), 1)

            // Every buffer replays the same ramp from startGain, so
            // non-interleaved channels stay in step with each other.
            var gain = startGain
            var n = 0
            while n < count {
                if gain < target { gain = min(gain + rampStep, target) }
                else if gain > target { gain = max(gain - rampStep, target) }
                let frameEnd = min(n + channels, count)
                while n < frameEnd {
                    destination[n] = source[n] * gain
                    n += 1
                }
            }
            for rest in count..<destinationCount { destination[rest] = 0 }
            endGain = gain
        }
        current.pointee = endGain
    }

    // MARK: - Core Audio helpers

    private static func defaultOutputDevice() -> AudioObjectID? {
        guard let device: AudioObjectID = property(AudioObjectID(kAudioObjectSystemObject),
                                                   kAudioHardwarePropertyDefaultOutputDevice),
              device != kAudioObjectUnknown else {
            return nil
        }
        return device
    }

    private static func ownProcessObject() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = getpid()
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid,
                                                &size, &processObject)
        guard status == noErr, processObject != kAudioObjectUnknown else { return nil }
        return processObject
    }

    private static func property<T>(_ object: AudioObjectID,
                                    _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else {
            return nil
        }
        return value.move()
    }
}
