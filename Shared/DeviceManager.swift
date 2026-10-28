//
//  DeviceManager.swift
//  LGTV Companion Shared
//
//  Coordinates device management, power events, and automation
//

import Foundation
import Combine

public enum DeviceManagerError: Error {
    case deviceNotFound
    case deviceDisabled
    case autoManageDisabled
    case connectionFailed
}

/// Live status snapshot of a TV, used by the menu bar UI.
public struct DeviceStatus: Equatable, Sendable {
    public var powerState: String?   // "Active", "Screen Off", "Active Standby", nil = unreachable
    public var volume: Int?
    public var muted: Bool?
    /// Whether the TV can change the volume of its current sound output.
    /// false on fixed-level outputs such as optical. nil = not reported.
    public var volumeAdjustable: Bool?

    public init(powerState: String? = nil, volume: Int? = nil, muted: Bool? = nil,
                volumeAdjustable: Bool? = nil) {
        self.powerState = powerState
        self.volume = volume
        self.muted = muted
        self.volumeAdjustable = volumeAdjustable
    }

    public var isReachable: Bool { powerState != nil }
    public var isScreenOn: Bool { powerState == "Active" }
}

/// Main actor: the published state, the hub logic and every callback into it
/// run on the main thread. The async methods suspend while they wait for the
/// TV; the sockets themselves live on `WebOSClient`'s own queue.
@MainActor
public class DeviceManager: ObservableObject {
    /// Shared instance so the AppDelegate can reach the manager during
    /// shutdown handling.
    public static let shared = DeviceManager(enableSoftwareVolume: true)

    @Published public var devices: [WebOSDevice] = []
    @Published public var deviceStatuses: [UUID: DeviceStatus] = [:]
    @Published public var isMonitoringPowerEvents = false
    @Published public var userIdleEnabled = false
    @Published public var userIdleTimeout: TimeInterval = DeviceManager.defaultUserIdleTimeout
    @Published public var mediaKeysEnabled = false

    /// What went wrong with the last TV command that failed, as a sentence for
    /// the user (cause and what to check). nil after the next command that
    /// worked. Background polling (status refresh) does not touch it, a TV
    /// that is switched off is a normal state there. Shown in the menu panel.
    @Published public private(set) var lastError: String?
    /// The TV `lastError` is about. nil when it is not about one TV.
    @Published public private(set) var lastErrorDeviceID: UUID?

    /// Mac-side software volume, used while the TV cannot change the volume
    /// itself (fixed-level output such as optical).
    @Published public private(set) var softwareVolumeEnabled = true
    /// Slider position 0...1 (not the gain, see SoftwareVolume.gain).
    @Published public private(set) var softwareVolumeLevel: Double = 1
    @Published public private(set) var softwareVolumeMuted = false
    /// True while the volume keys and the menu slider drive the software volume.
    @Published public private(set) var softwareVolumeActive = false
    /// Called on the main thread after a keyboard key changed the volume the
    /// app controls itself: software volume or speaker volume (level 0...1,
    /// muted). The keys are swallowed then, so the app shows its own display. Not called for the menu
    /// slider, which already shows the value.
    public var onVolumeKeyFeedback: (@MainActor (Double, Bool) -> Void)?

    /// Bluetooth control of Edifier speakers (real volume, Sub Out). Idle
    /// until switched on in Settings.
    public let speakers: EdifierSpeakerController
    /// Sound selection, night mode and wake behavior of the speakers.
    public private(set) lazy var speakerAutomation = SpeakerAutomation(speakers: speakers, defaults: userDefaults)

    /// Apps allowed to keep the TV on while they hold a display-sleep
    /// assertion (i.e. while playing video). Persisted by bundle ID so the
    /// choice survives restarts even when the app isn't running.
    @Published public var assertionAllowlist: [AssertingApp] = []

    private var clients: [UUID: WebOSClient] = [:]
    /// One per client: shares a running connect/register between commands.
    private var sessions: [UUID: TVSession] = [:]
    private var powerMonitor: PowerEventMonitor?
    private var idleMonitor: UserIdleMonitor?
    private var displayMonitor: DisplayConfigurationMonitor?
    private var mediaKeyMonitor: MediaKeyMonitor?
    private var keepaliveTimer: Timer?

    /// nil unless explicitly enabled. Only one process may tap the system
    /// audio: two taps would each mute and replay it.
    private let softwareVolumeController: SoftwareVolumeController?
    /// Last answer of the primary TV to "can you change the volume?".
    /// Persisted so a restart does not play at full level until the first
    /// status poll comes back, and so one failed poll does not drop the
    /// attenuation.
    private var tvCanAdjustVolume: Bool?

    /// Idle time before the TVs are switched off: 5 minutes.
    public static let defaultUserIdleTimeout: TimeInterval = 300

    private let userDefaults: UserDefaults
    private let devicesKey = "lgtvcompanion.devices"
    private let settingsKey = "lgtvcompanion.settings"
    /// Pairing keys live here, not in the preferences file.
    private let pairingKeyStore: PairingKeyStoring

    /// WoL packets right after wake often get lost (network interface still
    /// coming up) — send several with a delay between.
    private static let wakeRetryCount = 5
    private static let wakeRetryDelayNs: UInt64 = 2_000_000_000 // 2s
    /// Status poll that keeps the TV connections warm.
    private static let keepaliveSeconds: TimeInterval = 60

    /// `userDefaults` is where devices, settings and the speakers' settings
    /// are stored; tests pass their own suite.
    public init(enableSoftwareVolume: Bool = false,
                pairingKeyStore: PairingKeyStoring = CachingPairingKeyStore(KeychainPairingKeyStore()),
                userDefaults: UserDefaults = .standard) {
        softwareVolumeController = enableSoftwareVolume ? SoftwareVolumeController() : nil
        self.pairingKeyStore = pairingKeyStore
        self.userDefaults = userDefaults
        speakers = EdifierSpeakerController(defaults: userDefaults)
        loadDevices()
        loadSettings()
        softwareVolumeController?.onOutputDeviceChanged = { [weak self] in
            // The tap is bound to the old output device. Rebuild it for the
            // new one, or drop it if the sound no longer goes to a display.
            self?.softwareVolumeController?.stop()
            self?.syncSoftwareVolume()
        }
        syncSoftwareVolume()
        speakers.onKeyVolumeChanged = { [weak self] level, muted in
            self?.onVolumeKeyFeedback?(level, muted)
        }
        speakers.onVolumeKnown = { [weak self] in
            self?.handOverSoftwareVolumeToSpeakers()
        }
        speakers.onReply = { [weak self] reply in
            self?.speakerAutomation.speakersReported(reply)
        }
        // Created now rather than on first use, so the night schedule runs
        // from launch.
        _ = speakerAutomation
        // Only auto-start when the permission is already there — otherwise
        // macOS would show the Accessibility prompt on every launch.
        if mediaKeysEnabled && MediaKeyMonitor.hasAccessibilityPermission {
            startMediaKeyMonitoring()
        }
    }

    // MARK: - Device Management

    public func addDevice(_ device: WebOSDevice) {
        devices.append(device)
        saveDevices()
    }

    public func updateDevice(_ device: WebOSDevice) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
            saveDevices()
            // Connection parameters may have changed — drop cached client.
            dropClient(for: device.id)
        }
    }

    public func removeDevice(_ device: WebOSDevice) {
        devices.removeAll { $0.id == device.id }
        dropClient(for: device.id)
        pairingKeyStore.delete(for: device.id)
        saveDevices()
    }

    private func dropClient(for deviceId: UUID) {
        clients[deviceId]?.disconnect()
        clients.removeValue(forKey: deviceId)
        sessions.removeValue(forKey: deviceId)
    }

    public func getClient(for device: WebOSDevice) -> WebOSClient {
        clientAndSession(for: device).client
    }

    private func clientAndSession(for device: WebOSDevice) -> (client: WebOSClient, session: TVSession) {
        if let client = clients[device.id], let session = sessions[device.id] {
            return (client, session)
        }

        let client = WebOSClient(device: device)
        // Persist new/updated pairing keys so the TV doesn't prompt again
        // on every connection (previously the key was written to a separate
        // UserDefaults key that was never read back).
        client.onPairingKeyUpdated = { [weak self] deviceId, key in
            MainThread.async { [weak self] in
                self?.storePairingKey(key, for: deviceId)
            }
        }
        // Volume and power changes pushed by the TV, so the UI and the
        // volume routing follow at once instead of at the next poll.
        client.onStatusUpdate = { [weak self] deviceId, update in
            MainThread.async { [weak self] in
                self?.applyStatusUpdate(update, for: deviceId)
            }
        }
        let session = TVSession(transport: client)
        clients[device.id] = client
        sessions[device.id] = session
        return (client, session)
    }

    /// Main thread. Merges a pushed change into the published status.
    private func applyStatusUpdate(_ update: WebOSStatusUpdate, for deviceId: UUID) {
        guard let device = devices.first(where: { $0.id == deviceId }) else { return }
        var status = deviceStatuses[deviceId] ?? DeviceStatus()

        switch update {
        case .audio(let volume, let muted, let adjustable):
            if let volume = volume { status.volume = volume }
            if let muted = muted { status.muted = muted }
            if let adjustable = adjustable { status.volumeAdjustable = adjustable }
            // Audio reports only come from a TV that is up.
            if status.powerState == nil { status.powerState = "Active" }
        case .power(let state):
            status.powerState = state
        }

        deviceStatuses[deviceId] = status
        noteVolumeAdjustable(status.volumeAdjustable, for: device)
    }

    private func storePairingKey(_ key: String, for deviceId: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        devices[index].pairingKey = key
        saveDevices()
    }

    // MARK: - Device Operations

    public func powerOnDevice(_ device: WebOSDevice, method: WakeOnLANMethod = .broadcast) async throws {
        guard device.enabled else {
            throw DeviceManagerError.deviceDisabled
        }

        // 1. If the TV is merely in screen-off / standby with the network
        //    stack up, a direct command is instant — try that first.
        if device.useScreenOff {
            if (try? await withConnectedClient(for: device, reportsFailure: false) { client in
                try await client.screenOn()
            }) != nil {
                return
            }
        }

        // 2. Otherwise Wake-on-LAN, repeated — single packets right after
        //    system wake are frequently lost.
        var lastWakeError: Error?
        for attempt in 0..<Self.wakeRetryCount {
            do {
                try await WakeOnLAN.wake(
                    macAddress: device.macAddress,
                    ipAddress: device.ipAddress,
                    method: method
                )
                lastWakeError = nil
            } catch {
                lastWakeError = error
            }
            if attempt < Self.wakeRetryCount - 1 {
                try await Task.sleep(nanoseconds: Self.wakeRetryDelayNs)
            }
        }
        if let lastWakeError = lastWakeError {
            recordFailure(of: "Wake on LAN", error: lastWakeError, device: device)
            throw lastWakeError
        }
    }

    public func powerOffDevice(_ device: WebOSDevice) async throws {
        guard device.enabled else {
            throw DeviceManagerError.deviceDisabled
        }

        try await withConnectedClient(for: device) { client in
            if device.useScreenOff {
                // Screen off: instant picture-off, instant resume, no reboot —
                // the right behavior when the TV is a monitor.
                try await client.screenOff()
            } else {
                try await client.powerOff()
            }
        }
    }

    /// Connects (and pairs if needed), runs the operation, keeps connection
    /// cached for reuse. A failure is logged and kept in `lastError`; pass
    /// `reportsFailure: false` for background work where a TV that is off is
    /// expected (status polling, trying a screen on before Wake on LAN).
    private func withConnectedClient<T>(
        for device: WebOSDevice,
        reportsFailure: Bool = true,
        _ operation: (WebOSClient) async throws -> T
    ) async throws -> T {
        do {
            let result = try await runOnConnectedClient(for: device, operation)
            if reportsFailure { clearLastError() }
            return result
        } catch {
            if reportsFailure { recordFailure(of: "TV command for \(device.name)", error: error, device: device) }
            throw error
        }
    }

    private func runOnConnectedClient<T>(
        for device: WebOSDevice,
        _ operation: (WebOSClient) async throws -> T
    ) async throws -> T {
        let (client, session) = clientAndSession(for: device)

        // Concurrent callers share one connect/register (see TVSession).
        try await session.ensureReady()

        do {
            return try await operation(client)
        } catch {
            // Stale connection? Reconnect once and retry, but only for
            // errors a fresh connection can fix.
            guard TVSession.isTransient(error) else { throw error }
            try await session.reconnect()
            return try await operation(client)
        }
    }

    private func recordFailure(of action: String, error: Error, device: WebOSDevice) {
        let cause = error.localizedDescription
        Log.tv.error("\(action, privacy: .public) failed: \(cause, privacy: .public)")
        let message = TVFailureText.message(for: error, tvName: device.name)
        lastError = message
        lastErrorDeviceID = device.id
    }

    private func clearLastError() {
        if lastError != nil { lastError = nil }
        if lastErrorDeviceID != nil { lastErrorDeviceID = nil }
    }

    // MARK: - Live Status & Direct Controls (Menu Bar)

    /// Fetches power state + audio status and publishes it.
    public func refreshStatus(for device: WebOSDevice) async {
        var status = DeviceStatus()
        if let result = try? await withConnectedClient(for: device, reportsFailure: false, { client -> DeviceStatus in
            let state = try await client.getPowerState()
            let audio = try? await client.getAudioStatus()
            return DeviceStatus(powerState: state, volume: audio?.volume, muted: audio?.muted,
                                volumeAdjustable: audio?.adjustable)
        }) {
            status = result
        }
        deviceStatuses[device.id] = status
        noteVolumeAdjustable(status.volumeAdjustable, for: device)
    }

    public func refreshAllStatuses() async {
        let snapshot = devices.filter { $0.enabled }
        await withTaskGroup(of: Void.self) { group in
            for device in snapshot {
                group.addTask { await self.refreshStatus(for: device) }
            }
        }
    }

    public func screenOn(_ device: WebOSDevice) async throws {
        try await withConnectedClient(for: device) { try await $0.screenOn() }
        await refreshStatus(for: device)
    }

    public func screenOff(_ device: WebOSDevice) async throws {
        try await withConnectedClient(for: device) { try await $0.screenOff() }
        await refreshStatus(for: device)
    }

    /// Builds a fresh connection and registers with the TV, even if the old
    /// one still looks healthy. Returns once the TV confirmed the pairing
    /// (the user may have to accept a prompt on the TV). Goes through the
    /// device's `TVSession`, so it cannot race another command's connect.
    public func pairDevice(_ device: WebOSDevice) async throws {
        guard device.enabled else {
            throw DeviceManagerError.deviceDisabled
        }
        let session = clientAndSession(for: device).session
        do {
            try await session.reconnect()
            clearLastError()
        } catch {
            recordFailure(of: "Pairing \(device.name)", error: error, device: device)
            throw error
        }
    }

    /// Reads the TV's current foreground input id (read-only). Used by the UI
    /// to capture which input the Mac is connected to (the "Detect" button).
    public func readForegroundInput(for device: WebOSDevice) async throws -> String? {
        try await withConnectedClient(for: device) { try await $0.getForegroundAppInfo() }
    }

    /// Full power-off, regardless of the useScreenOff setting.
    public func fullPowerOff(_ device: WebOSDevice) async throws {
        try await withConnectedClient(for: device) { try await $0.powerOff() }
        deviceStatuses[device.id] = DeviceStatus()
    }

    public func setVolume(_ volume: Int, for device: WebOSDevice) async throws {
        try await withConnectedClient(for: device) { try await $0.setVolume(volume) }
    }

    public func setMute(_ muted: Bool, for device: WebOSDevice) async throws {
        try await withConnectedClient(for: device) { try await $0.setMute(muted) }
    }

    public func switchInput(_ inputId: String, for device: WebOSDevice) async throws {
        try await withConnectedClient(for: device) { try await $0.switchInput(inputId) }
    }

    public func testDevice(_ device: WebOSDevice) async -> (powerOn: Bool, powerOff: Bool) {
        var powerOnSuccess = false
        var powerOffSuccess = false

        do {
            try await powerOnDevice(device)
            powerOnSuccess = true

            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

            try await powerOffDevice(device)
            powerOffSuccess = true
        } catch {
            Log.tv.error("Device test failed: \(error.localizedDescription, privacy: .public)")
        }

        return (powerOnSuccess, powerOffSuccess)
    }

    // MARK: - Power Event Monitoring

    public func startPowerEventMonitoring() {
        guard !isMonitoringPowerEvents else { return }

        powerMonitor = PowerEventMonitor()
        powerMonitor?.onPowerEvent = { [weak self] event, completion in
            self?.handlePowerEvent(event, completion: completion)
        }

        displayMonitor = DisplayConfigurationMonitor()
        displayMonitor?.onDisplayConfigurationChanged = { [weak self] in
            self?.handleDisplayConfigurationChange()
        }

        if userIdleEnabled {
            startUserIdleMonitoring()
        }

        // Keep connections warm: a cold wss handshake + register can take
        // seconds — too slow when the Mac is about to sleep. A periodic
        // status poll keeps the sockets open so power-off is a single send.
        keepaliveTimer?.invalidate()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: Self.keepaliveSeconds, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.refreshAllStatuses() }
        }
        keepaliveTimer?.tolerance = TimerTolerance.tolerance(for: Self.keepaliveSeconds)
        Task { await self.refreshAllStatuses() } // warm up immediately

        isMonitoringPowerEvents = true
    }

    public func stopPowerEventMonitoring() {
        powerMonitor = nil
        displayMonitor = nil
        idleMonitor?.stopMonitoring()
        idleMonitor = nil
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        isMonitoringPowerEvents = false
    }

    /// Turns off all auto-managed devices. Used by the shutdown handler.
    /// - Parameter fullOff: true = real power-off regardless of the
    ///   screen-off setting (right choice when the Mac shuts down —
    ///   otherwise the TV would stay on behind a dark screen).
    public func powerOffManagedDevices(fullOff: Bool = false) async {
        // Skip TVs currently showing a non-Mac input (e.g. a console).
        let managed = managedDevices
        let targets = await devicesShowingMacInput(managed)
        await withTaskGroup(of: Void.self) { group in
            for device in targets {
                group.addTask {
                    if fullOff {
                        _ = try? await self.fullPowerOff(device)
                    } else {
                        _ = try? await self.powerOffDevice(device)
                    }
                }
            }
        }
    }

    private func startUserIdleMonitoring() {
        idleMonitor = UserIdleMonitor(idleThreshold: userIdleTimeout)
        idleMonitor?.allowedAssertionBundleIDs = Set(assertionAllowlist.map { $0.bundleID })
        idleMonitor?.onIdleStateChanged = { [weak self] isIdle in
            self?.handleUserIdleStateChange(isIdle)
        }
        idleMonitor?.startMonitoring()
    }

    // MARK: - Keep-Awake Allowlist

    /// Apps that are right now holding a display-sleep assertion (playing
    /// video). Used by the settings UI to offer them for the allowlist.
    public func currentDisplaySleepApps() -> [AssertingApp] {
        DisplaySleepAssertions.currentAssertingApps()
    }

    public func isAppAllowed(_ bundleID: String) -> Bool {
        assertionAllowlist.contains { $0.bundleID == bundleID }
    }

    public func setAppAllowed(_ app: AssertingApp, allowed: Bool) {
        if allowed {
            if !isAppAllowed(app.bundleID) {
                assertionAllowlist.append(app)
            }
        } else {
            assertionAllowlist.removeAll { $0.bundleID == app.bundleID }
        }
        saveSettings()
        idleMonitor?.allowedAssertionBundleIDs = Set(assertionAllowlist.map { $0.bundleID })
    }

    // MARK: - Event Handlers

    private var managedDevices: [WebOSDevice] {
        devices.filter { $0.autoManage && $0.enabled }
    }

    /// `completion` MUST be called for `.systemWillSleep` — the monitor
    /// delays actual system sleep until then.
    private func handlePowerEvent(_ event: PowerEvent, completion: @escaping () -> Void) {
        let targets = managedDevices

        Task {
            switch event {
            case .systemWillSleep, .displayWillSleep,
                 .systemWillShutdown, .systemWillRestart:
                await self.powerOffAll(targets)

            case .systemDidWake, .displayDidWake:
                // The tap does not reliably survive sleep. Rebuild it.
                softwareVolumeController?.stop()
                softwareVolumeController?.refreshOutputDevice()
                syncSoftwareVolume()
                speakerAutomation.macDidWake()
                await self.powerOnAll(targets)
            }
            completion()
        }
    }

    /// All devices concurrently — one slow TV must not delay the others
    /// (especially while the system is waiting to sleep). Devices whose TV is
    /// currently showing a non-Mac input (e.g. a console on another HDMI port)
    /// are skipped, so automatic power-off never interrupts them.
    private func powerOffAll(_ targets: [WebOSDevice]) async {
        let eligible = await devicesShowingMacInput(targets)
        await withTaskGroup(of: Void.self) { group in
            for device in eligible {
                group.addTask { _ = try? await self.powerOffDevice(device) }
            }
        }
    }

    /// Keeps only devices whose TV is currently showing the Mac's input.
    private func devicesShowingMacInput(_ targets: [WebOSDevice]) async -> [WebOSDevice] {
        await withTaskGroup(of: (WebOSDevice, Bool).self) { group in
            for device in targets {
                group.addTask { (device, await self.tvShowsMacInput(device)) }
            }
            var result: [WebOSDevice] = []
            for await (device, shows) in group where shows {
                result.append(device)
            }
            return result
        }
    }

    /// Whether the TV currently shows the Mac's input. Returns true (i.e. allow
    /// power-off) when no Mac input is configured or the input can't be read —
    /// a flaky query must never permanently disable the core power-off.
    private func tvShowsMacInput(_ device: WebOSDevice) async -> Bool {
        guard let macInput = device.macInputAppId else { return true }
        guard let currentApp = try? await withConnectedClient(
                  for: device, reportsFailure: false, { try await $0.getForegroundAppInfo() }) else {
            return true
        }
        return currentApp == macInput
    }

    private func powerOnAll(_ targets: [WebOSDevice]) async {
        await withTaskGroup(of: Void.self) { group in
            for device in targets {
                group.addTask { _ = try? await self.powerOnDevice(device) }
            }
        }
    }

    private func handleDisplayConfigurationChange() {
        guard let displayMonitor = displayMonitor else { return }

        let displayCount = displayMonitor.getActiveDisplayCount()
        let targets = managedDevices

        Task {
            // If no displays are connected, turn off TVs
            if displayCount == 0 {
                await self.powerOffAll(targets)
            }
        }
    }

    private func handleUserIdleStateChange(_ isIdle: Bool) {
        let targets = managedDevices
        Task {
            if isIdle {
                await self.powerOffAll(targets)
            } else {
                await self.powerOnAll(targets)
            }
        }
    }

    // MARK: - Media Keys (keyboard volume → TV volume)

    /// Enables/disables routing of the keyboard volume keys to the TV.
    /// Requires Accessibility permission to fully take over the keys
    /// (otherwise the Mac volume OSD reacts as well).
    public func setMediaKeysEnabled(_ enabled: Bool) {
        mediaKeysEnabled = enabled
        saveSettings()

        if enabled {
            if MediaKeyMonitor.hasAccessibilityPermission {
                startMediaKeyMonitoring()
            } else {
                // Prompt once; the tap is installed later by
                // ensureMediaKeyTap() once the user granted access.
                MediaKeyMonitor.requestAccessibilityPermission()
            }
        } else {
            mediaKeyMonitor?.stop()
            mediaKeyMonitor = nil
        }
    }

    /// Whether this launch already showed the Accessibility prompt. Keeps
    /// ensureMediaKeyTap (called from several views) from re-prompting.
    private var didPromptForAccessibility = false

    /// Re-installs the event tap if media keys are enabled but the tap
    /// couldn't be created earlier (e.g. Accessibility permission was
    /// granted only after launch). Call this periodically / on UI focus.
    public func ensureMediaKeyTap() {
        guard mediaKeysEnabled else { return }
        if let monitor = mediaKeyMonitor, monitor.isUsingEventTap { return }
        if MediaKeyMonitor.hasAccessibilityPermission {
            startMediaKeyMonitoring()
        } else if !didPromptForAccessibility {
            // Feature is enabled but the permission is missing — typically
            // because an app update re-signed the binary (ad-hoc signatures
            // change every build) and macOS silently invalidated the old
            // grant. Prompt once per launch so the user can re-grant without
            // hunting for the settings toggle; the keys silently doing
            // nothing is worse than one extra dialog.
            didPromptForAccessibility = true
            MediaKeyMonitor.requestAccessibilityPermission()
        }
    }

    private func startMediaKeyMonitoring() {
        let monitor = MediaKeyMonitor()
        monitor.onMediaKey = { [weak self] key in
            // Returns whether the key was routed to a TV; the monitor only
            // swallows it when true.
            self?.handleMediaKey(key) ?? false
        }
        monitor.start()
        mediaKeyMonitor = monitor
    }

    /// Routes a media key to the first enabled device. Returns whether a
    /// target existed: the caller (MediaKeyMonitor) only swallows the key when
    /// this is true, so with no enabled device the Mac keeps normal volume
    /// control instead of the key being eaten with nothing happening.
    /// Called on the main thread (the event-tap source runs on the main run loop).
    @discardableResult
    private func handleMediaKey(_ key: MediaKeyEvent) -> Bool {
        // See VolumeKeyRoute.route for the order. Real speaker control beats
        // everything else: it changes the level in the speakers themselves,
        // for every source and without digital loss. If the speakers were just
        // found unreachable, the route falls through to the next target.
        let device = devices.first(where: { $0.enabled })
        let route = VolumeKeyRoute.route(speakersCanHandleVolumeKeys: speakers.canHandleVolumeKeys,
                                         hasEnabledTV: device != nil,
                                         softwareVolumeActive: softwareVolumeActive,
                                         tvCanAdjustVolume: tvCanAdjustVolume)
        switch route {
        case .speakers:
            speakers.handleVolumeKey(key)
            return true
        case .softwareVolume:
            handleSoftwareVolumeKey(key)
            return true
        case .passThrough:
            // No enabled TV, or the TV cannot change the volume and the Mac's
            // sound is not going to a display: the keys belong to macOS.
            return false
        case .tv:
            break
        }
        guard let device else { return false }

        switch key {
        case .volumeUp:
            enqueueVolumeStep(+1, for: device)
        case .volumeDown:
            enqueueVolumeStep(-1, for: device)
        case .mute:
            Task {
                // Toggle off the TV's live state, in one connection. Reading
                // the cached deviceStatuses here would both race the main
                // thread and, before the first status refresh, wrongly
                // assume "unmuted" and send mute=true to an already-muted TV.
                try? await self.withConnectedClient(for: device) { client in
                    let live = try? await client.getAudioStatus()
                    let currentlyMuted = live?.muted ?? false
                    try await client.setMute(!currentlyMuted)
                }
                await self.publishAudioStatus(for: device)
            }
        }
        return true
    }

    // MARK: Volume key pipeline

    /// Net outstanding volume steps (+ up / − down). Main-thread only.
    private var pendingVolumeSteps = 0
    /// Whether the serial volume worker task is currently draining the counter.
    private var volumeWorkerActive = false

    /// Coalesces rapid volume-key presses into a counter drained by ONE serial
    /// worker task. The previous per-press `Task { withConnectedClient … }`
    /// spawned an unbounded number of concurrent tasks under key-repeat
    /// (~15 events/s while the key is held), each doing two network round
    /// trips — they overtook each other and made the volume lag and jump.
    /// Runs on the main thread (see handleMediaKey).
    private func enqueueVolumeStep(_ delta: Int, for device: WebOSDevice) {
        pendingVolumeSteps += delta
        guard !volumeWorkerActive else { return }
        volumeWorkerActive = true

        Task {
            while true {
                let step = self.takeNextVolumeStep()
                if step == 0 { break }

                do {
                    try await self.withConnectedClient(for: device) { client in
                        if step > 0 { try await client.volumeUp() }
                        else { try await client.volumeDown() }
                    }
                } catch {
                    // TV unreachable — drop whatever is still queued; replaying
                    // stale key presses seconds later would be worse.
                    self.pendingVolumeSteps = 0
                    break
                }
            }

            // One status refresh after the burst, not one per key press.
            await self.publishAudioStatus(for: device)

            self.volumeWorkerActive = false
            // Presses that arrived while the status was being published
            // restart the worker so they aren't stranded in the counter.
            if self.pendingVolumeSteps != 0 {
                let d = self.pendingVolumeSteps > 0 ? 1 : -1
                self.pendingVolumeSteps -= d
                self.enqueueVolumeStep(d, for: device)
            }
        }
    }

    /// Takes one outstanding step off the counter: +1, -1, or 0 when empty.
    private func takeNextVolumeStep() -> Int {
        if pendingVolumeSteps > 0 { pendingVolumeSteps -= 1; return 1 }
        if pendingVolumeSteps < 0 { pendingVolumeSteps += 1; return -1 }
        return 0
    }

    /// Fetches volume/mute once and publishes it so the menu-bar slider follows.
    private func publishAudioStatus(for device: WebOSDevice) async {
        guard let audio = try? await withConnectedClient(for: device, reportsFailure: false, { try await $0.getAudioStatus() }) else {
            return
        }
        var status = deviceStatuses[device.id] ?? DeviceStatus()
        status.volume = audio.volume
        status.muted = audio.muted
        if status.powerState == nil { status.powerState = "Active" }
        deviceStatuses[device.id] = status
    }

    // MARK: - Software Volume (Mac-side, for fixed-level TV outputs)

    public func setSoftwareVolumeEnabled(_ enabled: Bool) {
        softwareVolumeEnabled = enabled
        saveSettings()
        syncSoftwareVolume()
    }

    /// Sets the slider level (0...1). Moving the slider also unmutes, like
    /// the macOS volume slider does.
    public func setSoftwareVolume(level: Double) {
        softwareVolumeLevel = SoftwareVolume.clamp(level)
        softwareVolumeMuted = false
        saveSettingsSoon()
        syncSoftwareVolume()
    }

    public func toggleSoftwareMute() {
        softwareVolumeMuted.toggle()
        saveSettingsSoon()
        syncSoftwareVolume()
    }

    private func handleSoftwareVolumeKey(_ key: MediaKeyEvent) {
        switch key {
        case .volumeUp:
            setSoftwareVolume(level: SoftwareVolume.stepped(softwareVolumeLevel, by: +1))
        case .volumeDown:
            setSoftwareVolume(level: SoftwareVolume.stepped(softwareVolumeLevel, by: -1))
        case .mute:
            toggleSoftwareMute()
        }
        onVolumeKeyFeedback?(softwareVolumeLevel, softwareVolumeMuted)
    }

    /// Delay between lowering the speakers and releasing the software
    /// attenuation during a hand-over, so the command has reached them.
    private static let handOverDelaySeconds: TimeInterval = 0.3

    /// When the speakers become controllable while the software volume is
    /// attenuating, move that attenuation into the speakers: two volume
    /// controls stacked on each other would be confusing. Order matters,
    /// speakers down first, then software back to 100 %, so it never gets
    /// louder in between.
    private func handOverSoftwareVolumeToSpeakers() {
        guard softwareVolumeActive, !softwareVolumeMuted, softwareVolumeLevel < 1,
              let speakerVolume = speakers.volume else { return }

        speakers.setVolume(SoftwareVolume.handOverVolume(speakerVolume: speakerVolume,
                                                         softwareLevel: softwareVolumeLevel))
        MainThread.asyncAfter(seconds: Self.handOverDelaySeconds) { [weak self] in
            self?.setSoftwareVolume(level: 1)
        }
    }

    /// Remembers whether the primary TV (the one the volume keys go to) can
    /// change the volume. An unknown answer keeps the previous one.
    private func noteVolumeAdjustable(_ adjustable: Bool?, for device: WebOSDevice) {
        guard let adjustable = adjustable,
              device.id == devices.first(where: { $0.enabled })?.id,
              adjustable != tvCanAdjustVolume else { return }
        tvCanAdjustVolume = adjustable
        saveSettings()
        syncSoftwareVolume()
    }

    /// Single place that decides whether the software volume is in charge and
    /// pushes the current gain to the audio tap. Main thread.
    private func syncSoftwareVolume() {
        guard let controller = softwareVolumeController else { return }

        let wanted = SoftwareVolume.shouldControl(
            enabled: softwareVolumeEnabled,
            tvCanAdjustVolume: tvCanAdjustVolume,
            outputIsDigitalDisplay: controller.outputIsDigitalDisplay
        )
        guard wanted else {
            controller.stop()
            softwareVolumeActive = false
            return
        }

        let gain = SoftwareVolume.gain(forLevel: softwareVolumeLevel, muted: softwareVolumeMuted)
        // If the tap cannot be built, hand the keys back to macOS rather
        // than swallowing them with no effect.
        softwareVolumeActive = controller.apply(gain: gain)
    }

    // MARK: - Settings

    public func updateUserIdleSettings(enabled: Bool, timeout: TimeInterval) {
        userIdleEnabled = enabled
        userIdleTimeout = timeout

        saveSettings()

        if isMonitoringPowerEvents {
            if enabled {
                idleMonitor?.stopMonitoring()
                startUserIdleMonitoring()
            } else {
                idleMonitor?.stopMonitoring()
                idleMonitor = nil
            }
        }
    }

    /// Returns everything the app stores to a fresh install: all TVs with
    /// their pairing keys, idle and media key options, the keep-awake list,
    /// software volume, and the speakers' settings. Launch at login is the
    /// system's and stays as it is.
    public func resetAllSettings() {
        for device in devices {
            removeDevice(device)
        }

        updateUserIdleSettings(enabled: false, timeout: Self.defaultUserIdleTimeout)
        assertionAllowlist = []

        mediaKeysEnabled = false
        mediaKeyMonitor?.stop()
        mediaKeyMonitor = nil

        softwareVolumeEnabled = true
        softwareVolumeLevel = 1
        softwareVolumeMuted = false
        tvCanAdjustVolume = nil
        syncSoftwareVolume()

        speakerAutomation.resetSettings()
        speakers.resetSettings()

        // Nothing of the old state may be written back by a pending save.
        pendingSettingsSave?.cancel()
        pendingSettingsSave = nil
        userDefaults.removeObject(forKey: settingsKey)
        userDefaults.removeObject(forKey: devicesKey)

        lastError = nil
        lastErrorDeviceID = nil
        deviceStatuses = [:]
    }

    // MARK: - Persistence

    private func saveDevices() {
        if let encoded = DevicePersistence.encode(devices, keyStore: pairingKeyStore) {
            userDefaults.set(encoded, forKey: devicesKey)
        }
    }

    private func loadDevices() {
        guard let data = userDefaults.data(forKey: devicesKey),
              let loaded = DevicePersistence.decode(data, keyStore: pairingKeyStore) else {
            return
        }
        devices = loaded.devices
        // A key still sitting in the file in plain text (older version) is
        // moved into the keychain by writing the list once.
        if loaded.needsResave {
            saveDevices()
        }
    }

    /// How long the volume keys wait for a further press before the level is
    /// written to the preferences. Holding a key repeats ~15 times a second.
    private static let settingsSaveDebounceSeconds: TimeInterval = 1
    private var pendingSettingsSave: DispatchWorkItem?

    /// Debounced saveSettings() for the volume keys and the menu slider.
    /// Main thread.
    private func saveSettingsSoon() {
        pendingSettingsSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSettings() }
        pendingSettingsSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settingsSaveDebounceSeconds, execute: work)
    }

    /// Writes a debounced save that has not run yet. Call before quitting.
    public func flushPendingSettings() {
        guard pendingSettingsSave != nil else { return }
        saveSettings()
    }

    private func saveSettings() {
        // Whatever was waiting is part of this write.
        pendingSettingsSave?.cancel()
        pendingSettingsSave = nil
        var settings: [String: Any] = [
            "userIdleEnabled": userIdleEnabled,
            "userIdleTimeout": userIdleTimeout,
            "mediaKeysEnabled": mediaKeysEnabled,
            "softwareVolumeEnabled": softwareVolumeEnabled,
            "softwareVolumeLevel": softwareVolumeLevel,
            "softwareVolumeMuted": softwareVolumeMuted,
            "assertionAllowlist": assertionAllowlist.map {
                ["bundleID": $0.bundleID, "name": $0.name]
            }
        ]
        if let tvCanAdjustVolume = tvCanAdjustVolume {
            settings["tvCanAdjustVolume"] = tvCanAdjustVolume
        }
        userDefaults.set(settings, forKey: settingsKey)
    }

    private func loadSettings() {
        guard let settings = userDefaults.dictionary(forKey: settingsKey) else {
            return
        }

        userIdleEnabled = settings["userIdleEnabled"] as? Bool ?? false
        userIdleTimeout = settings["userIdleTimeout"] as? TimeInterval ?? Self.defaultUserIdleTimeout
        mediaKeysEnabled = settings["mediaKeysEnabled"] as? Bool ?? false
        softwareVolumeEnabled = settings["softwareVolumeEnabled"] as? Bool ?? true
        softwareVolumeLevel = SoftwareVolume.clamp(settings["softwareVolumeLevel"] as? Double ?? 1)
        softwareVolumeMuted = settings["softwareVolumeMuted"] as? Bool ?? false
        tvCanAdjustVolume = settings["tvCanAdjustVolume"] as? Bool

        if let raw = settings["assertionAllowlist"] as? [[String: String]] {
            assertionAllowlist = raw.compactMap { entry in
                guard let bundleID = entry["bundleID"], let name = entry["name"] else {
                    return nil
                }
                return AssertingApp(bundleID: bundleID, name: name)
            }
        }
    }
}
