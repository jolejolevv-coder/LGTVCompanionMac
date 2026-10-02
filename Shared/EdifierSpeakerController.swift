//
//  EdifierSpeakerController.swift
//  LGTV Companion Shared
//
//  Controls Edifier M90 speakers over Bluetooth LE: real speaker volume and
//  the Sub Out level. Protocol details live in EdifierProtocol.
//
//  The speakers accept ONE Bluetooth LE client at a time. While this app is
//  connected, the EDIFIER ConneX phone app cannot reach them. So the app
//  connects only when there is something to do and disconnects again after a
//  short idle period.
//
//  Everything here runs on the main thread (the Bluetooth callbacks are
//  delivered on the main queue).
//

import Foundation
import CoreBluetooth

public final class EdifierSpeakerController: NSObject, ObservableObject {
    public enum ConnectionState: Equatable {
        case idle          // not connected, will connect on demand
        case connecting
        case connected
        case unavailable   // last attempt failed, or Bluetooth is off/denied
    }

    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var state: ConnectionState = .idle
    /// nil until the speaker reported it.
    @Published public private(set) var volume: Int?
    @Published public private(set) var maxVolume = EdifierProtocol.defaultMaxVolume
    @Published public private(set) var subOut: EdifierSubOutLevel?
    @Published public private(set) var deviceName: String?
    @Published public private(set) var input: EdifierInput?
    @Published public private(set) var eqPreset: EdifierEQPreset?
    /// Gains of the Custom slot in dB, one per band.
    @Published public private(set) var customEQ: [Double]?
    /// Upper bound applied to every volume change while set (night mode).
    @Published public private(set) var volumeLimit: Int?
    /// True while the mute key has turned the volume down to zero.
    @Published public private(set) var isMuted = false

    /// Called after a keyboard key changed the volume: level 0...1, muted.
    public var onKeyVolumeChanged: ((Double, Bool) -> Void)?
    /// Called once per connection, as soon as the speaker's volume is known.
    public var onVolumeKnown: (() -> Void)?
    /// Called after a value the speaker reported was taken over, with the
    /// reply it came from. Lets the caller react to exactly that fresh value
    /// instead of to cached ones.
    public var onReply: ((EdifierReply) -> Void)?

    /// True while a multi-frame change (an EQ curve) is still being sent. A
    /// state read during that time can show a half-written curve.
    public var hasPendingWrites: Bool {
        !pendingFrames.isEmpty || framesInFlight > 0
    }
    private var framesInFlight = 0

    /// Volume units per key press. The speaker has 50 steps; 2 per press
    /// gives 25 presses for the full range, fine enough for a volume knob.
    private static let volumeUnitsPerKey = 2
    /// Disconnect this long after the last activity, so the phone app can
    /// reach the speakers again.
    private static let idleDisconnectSeconds: TimeInterval = 20
    /// Give up on a connection attempt after this long.
    private static let connectTimeoutSeconds: TimeInterval = 6
    /// After a failed attempt, leave the volume keys to the fallback for this
    /// long instead of stalling on every key press.
    private static let retryPauseSeconds: TimeInterval = 60
    /// Gap between frames of a multi-frame change (nine EQ bands). The
    /// speaker drops writes that arrive back to back.
    private static let frameSpacingSeconds: TimeInterval = 0.08
    /// The speaker needs a moment after an input switch before it reports
    /// the new input; an immediate query still returns the old one.
    private static let inputSettleSeconds: TimeInterval = 3

    private static let enabledKey = "lgtvcompanion.speakers.enabled"
    private static let peripheralKey = "lgtvcompanion.speakers.peripheral"

    private let defaults = UserDefaults.standard
    private let advertisedService = CBUUID(string: EdifierProtocol.advertisedServiceUUID)
    private let controlService = CBUUID(string: EdifierProtocol.serviceUUID)
    private let notifyCharacteristic = CBUUID(string: EdifierProtocol.notifyCharacteristicUUID)
    private let writeCharacteristic = CBUUID(string: EdifierProtocol.writeCharacteristicUUID)

    /// Created on first use: creating it triggers the Bluetooth permission
    /// prompt, which must not appear unless the feature is switched on.
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writer: CBCharacteristic?

    private var pendingKeySteps = 0
    private var pendingMuteToggle = false
    /// Set by a keyboard key; the next applied change then reports back for
    /// the on-screen display. UI changes leave it unset.
    private var keyFeedbackPending = false
    private var pendingVolume: Int?
    private var pendingSubOut: EdifierSubOutLevel?
    /// Frames queued by setInput / setEQPreset / applyEQCurve while not yet
    /// connected. Each entry is sent in order with spacing.
    private var pendingFrames: [Data] = []
    private var volumeBeforeMute: Int?
    private var announcedVolume = false

    private var idleWork: DispatchWorkItem?
    private var timeoutWork: DispatchWorkItem?
    private var retryNotBefore: Date?

    public override init() {
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        super.init()
    }

    // MARK: - Public API

    /// Whether the volume keys should go to the speakers right now. False
    /// while the feature is off or the speakers were just found unreachable.
    public var canHandleVolumeKeys: Bool {
        guard isEnabled else { return false }
        if let retryNotBefore = retryNotBefore, Date() < retryNotBefore { return false }
        return true
    }

    public var hasKnownSpeaker: Bool {
        defaults.string(forKey: Self.peripheralKey) != nil
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled {
            retryNotBefore = nil
            connectIfNeeded()
        } else {
            disconnect()
        }
    }

    /// Forgets the remembered speaker, so the next connection searches again.
    public func forgetSpeaker() {
        defaults.removeObject(forKey: Self.peripheralKey)
        disconnect()
        deviceName = nil
    }

    /// Connects if needed and re-reads volume and Sub Out. An explicit user
    /// action, so it also retries during the pause after a failed attempt.
    public func refresh() {
        guard isEnabled else { return }
        retryNotBefore = nil
        if state == .connected {
            queryState()
            touch()
        } else {
            connectIfNeeded()
        }
    }

    /// Mute or unmute from the UI. Unlike the mute key it does not trigger
    /// the on-screen level display.
    public func toggleMute() {
        pendingMuteToggle.toggle()
        connectIfNeeded()
        applyPending()
    }

    public func handleVolumeKey(_ key: MediaKeyEvent) {
        keyFeedbackPending = true
        switch key {
        case .volumeUp: pendingKeySteps += 1
        case .volumeDown: pendingKeySteps -= 1
        case .mute: pendingMuteToggle.toggle()
        }
        connectIfNeeded()
        applyPending()
    }

    public func setVolume(_ newVolume: Int) {
        pendingVolume = newVolume
        connectIfNeeded()
        applyPending()
    }

    public func setSubOut(_ level: EdifierSubOutLevel) {
        pendingSubOut = level
        connectIfNeeded()
        applyPending()
    }

    public func setInput(_ newInput: EdifierInput) {
        input = newInput
        enqueue([EdifierProtocol.setInput(newInput)])
        // Confirm once the speaker has settled on the new input.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.inputSettleSeconds) { [weak self] in
            guard let self = self, self.state == .connected else { return }
            self.send(EdifierProtocol.queryInput())
        }
    }

    public func setEQPreset(_ preset: EdifierEQPreset) {
        eqPreset = preset
        enqueue([EdifierProtocol.setEQPreset(preset), EdifierProtocol.queryEQPreset()])
    }

    /// Writes all bands into the speakers' Custom slot and selects it. The
    /// bands only take effect while Custom is selected, so it is selected
    /// first. Reads both back afterwards.
    public func applyEQCurve(_ gains: [Double]) {
        let snapped = gains.map(EdifierProtocol.snappedGain)
        var frames = [EdifierProtocol.setEQPreset(.custom)]
        for (index, gain) in snapped.enumerated() {
            guard let frame = EdifierProtocol.setEQBand(index: index, gainDB: gain) else { continue }
            frames.append(frame)
        }
        frames += [EdifierProtocol.queryEQPreset(), EdifierProtocol.queryCustomEQ()]

        eqPreset = .custom
        customEQ = snapped
        enqueue(frames)
    }

    /// Changes one band of the Custom slot (the equalizer sliders).
    public func setEQBand(index: Int, gainDB: Double) {
        guard var gains = customEQ, gains.indices.contains(index),
              let frame = EdifierProtocol.setEQBand(index: index, gainDB: gainDB) else { return }
        gains[index] = EdifierProtocol.snappedGain(gainDB)
        customEQ = gains
        enqueue([frame])
    }

    /// Caps the volume (nil removes the cap). A volume above the new cap is
    /// lowered right away.
    public func setVolumeLimit(_ limit: Int?) {
        volumeLimit = limit
        guard let limit = limit, let current = volume, current > limit else { return }
        setVolume(limit)
    }

    private func enqueue(_ frames: [Data]) {
        pendingFrames += frames
        connectIfNeeded()
        applyPending()
    }

    // MARK: - Connection

    private func connectIfNeeded() {
        guard isEnabled, state != .connected, state != .connecting else { return }
        if let retryNotBefore = retryNotBefore, Date() < retryNotBefore { return }

        state = .connecting
        scheduleTimeout()

        if let central = central {
            beginConnecting(central)
        } else {
            // Continues in centralManagerDidUpdateState.
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    private func beginConnecting(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }

        // A remembered speaker connects directly, without waiting for its
        // next advertisement. Scan as well: the identifier changes if the
        // speakers were reset.
        if let saved = defaults.string(forKey: Self.peripheralKey),
           let identifier = UUID(uuidString: saved),
           let known = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            connect(known, using: central)
        }
        central.scanForPeripherals(withServices: [advertisedService], options: nil)
    }

    private func connect(_ target: CBPeripheral, using central: CBCentralManager) {
        guard peripheral == nil else { return }
        peripheral = target
        target.delegate = self
        central.connect(target, options: nil)
    }

    private func disconnect() {
        cancelTimers()
        central?.stopScan()
        if let peripheral = peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        resetConnection(to: .idle)
    }

    private func resetConnection(to newState: ConnectionState) {
        peripheral = nil
        writer = nil
        announcedVolume = false
        state = newState
    }

    private func failConnection() {
        central?.stopScan()
        if let peripheral = peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        // Key presses queued for this attempt would arrive seconds late.
        pendingKeySteps = 0
        pendingMuteToggle = false
        keyFeedbackPending = false
        pendingVolume = nil
        pendingSubOut = nil
        pendingFrames = []
        retryNotBefore = Date().addingTimeInterval(Self.retryPauseSeconds)
        cancelTimers()
        resetConnection(to: .unavailable)
    }

    private func scheduleTimeout() {
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.state == .connecting else { return }
            self.failConnection()
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeoutSeconds, execute: work)
    }

    /// Restarts the idle countdown.
    private func touch() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.disconnect() }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleDisconnectSeconds, execute: work)
    }

    private func cancelTimers() {
        idleWork?.cancel()
        timeoutWork?.cancel()
        idleWork = nil
        timeoutWork = nil
    }

    // MARK: - Commands

    private func send(_ frame: Data) {
        guard let peripheral = peripheral, let writer = writer else { return }
        let type: CBCharacteristicWriteType =
            writer.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(frame, for: writer, type: type)
        touch()
    }

    private func queryState() {
        send(EdifierProtocol.queryVolume())
        send(EdifierProtocol.querySubOut())
        send(EdifierProtocol.queryName())
        send(EdifierProtocol.queryInput())
        send(EdifierProtocol.queryEQPreset())
        send(EdifierProtocol.queryCustomEQ())
    }

    private func sendSpaced(_ frames: [Data]) {
        framesInFlight += frames.count
        for (position, frame) in frames.enumerated() {
            let delay = Double(position) * Self.frameSpacingSeconds
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.framesInFlight -= 1
                self.send(frame)
            }
        }
    }

    /// Sends whatever the user asked for while not yet connected, or just now.
    /// Volume changes wait until the speaker told us its current volume.
    private func applyPending() {
        guard state == .connected else { return }

        if !pendingFrames.isEmpty {
            let frames = pendingFrames
            pendingFrames = []
            sendSpaced(frames)
        }

        if let level = pendingSubOut {
            pendingSubOut = nil
            send(EdifierProtocol.setSubOut(level))
            // Read back instead of assuming: an acknowledgement alone does
            // not prove the setting changed.
            send(EdifierProtocol.querySubOut())
        }

        guard let current = volume else { return }

        if let absolute = pendingVolume {
            pendingVolume = nil
            volumeBeforeMute = nil
            isMuted = false
            writeVolume(absolute)
        }

        guard pendingKeySteps != 0 || pendingMuteToggle else { return }
        let steps = pendingKeySteps
        let toggleMute = pendingMuteToggle
        pendingKeySteps = 0
        pendingMuteToggle = false

        if toggleMute {
            if let restore = volumeBeforeMute {
                volumeBeforeMute = nil
                isMuted = false
                writeVolume(restore)
            } else {
                volumeBeforeMute = volume ?? current
                isMuted = true
                writeVolume(0)
            }
        }
        if steps != 0 {
            // A volume key while muted unmutes and continues from the level
            // before muting, like macOS does.
            let base = volumeBeforeMute ?? volume ?? current
            volumeBeforeMute = nil
            isMuted = false
            writeVolume(base + steps * Self.volumeUnitsPerKey)
        }

        if keyFeedbackPending, let now = volume, maxVolume > 0 {
            keyFeedbackPending = false
            onKeyVolumeChanged?(Double(now) / Double(maxVolume), isMuted)
        }
    }

    private func writeVolume(_ newVolume: Int) {
        let ceiling = min(maxVolume, volumeLimit ?? maxVolume)
        let clamped = min(max(newVolume, 0), ceiling)
        send(EdifierProtocol.setVolume(clamped, maximum: maxVolume))
        volume = clamped
    }

    private func handle(_ reply: EdifierReply) {
        switch reply {
        case .volume(let maximum, let current):
            if maximum > 0 { maxVolume = maximum }
            // While muted by us the speaker reports 0; keep that as is.
            volume = current
            if !announcedVolume {
                announcedVolume = true
                onVolumeKnown?()
            }
            applyPending()
        case .subOut(let level):
            subOut = level
        case .name(let name):
            deviceName = name
        case .input(let reported):
            input = reported
        case .eqPreset(let preset):
            eqPreset = preset
        case .customEQ(let gains):
            customEQ = gains
        case .other:
            return
        }
        onReply?(reply)
    }
}

// MARK: - CBCentralManagerDelegate

extension EdifierSpeakerController: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if state == .connecting { beginConnecting(central) }
        case .unauthorized, .unsupported, .poweredOff:
            if state == .connecting { failConnection() } else { resetConnection(to: .unavailable) }
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover discovered: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        connect(discovered, using: central)
    }

    public func centralManager(_ central: CBCentralManager, didConnect connected: CBPeripheral) {
        central.stopScan()
        defaults.set(connected.identifier.uuidString, forKey: Self.peripheralKey)
        connected.discoverServices([controlService])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect failed: CBPeripheral, error: Error?) {
        // Let the scan find it again within the timeout.
        if peripheral === failed { peripheral = nil }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral gone: CBPeripheral, error: Error?) {
        guard peripheral === gone else { return }
        cancelTimers()
        resetConnection(to: .idle)
    }
}

// MARK: - CBPeripheralDelegate

extension EdifierSpeakerController: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == controlService }) else {
            failConnection()
            return
        }
        peripheral.discoverCharacteristics([notifyCharacteristic, writeCharacteristic], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        guard let notifier = characteristics.first(where: { $0.uuid == notifyCharacteristic }),
              let writer = characteristics.first(where: { $0.uuid == writeCharacteristic }) else {
            failConnection()
            return
        }
        self.writer = writer
        peripheral.setNotifyValue(true, for: notifier)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.isNotifying else {
            failConnection()
            return
        }
        timeoutWork?.cancel()
        retryNotBefore = nil
        state = .connected
        queryState()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        for reply in EdifierProtocol.parse(data) {
            handle(reply)
        }
    }
}
