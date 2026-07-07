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
public struct DeviceStatus: Equatable {
    public var powerState: String?   // "Active", "Screen Off", "Active Standby", nil = unreachable
    public var volume: Int?
    public var muted: Bool?

    public init(powerState: String? = nil, volume: Int? = nil, muted: Bool? = nil) {
        self.powerState = powerState
        self.volume = volume
        self.muted = muted
    }

    public var isReachable: Bool { powerState != nil }
    public var isScreenOn: Bool { powerState == "Active" }
}

public class DeviceManager: ObservableObject {
    /// Shared instance so the AppDelegate can reach the manager during
    /// shutdown handling.
    public static let shared = DeviceManager()

    @Published public var devices: [WebOSDevice] = []
    @Published public var deviceStatuses: [UUID: DeviceStatus] = [:]
    @Published public var isMonitoringPowerEvents = false
    @Published public var userIdleEnabled = false
    @Published public var userIdleTimeout: TimeInterval = 300 // 5 minutes
    @Published public var mediaKeysEnabled = false

    /// Apps allowed to keep the TV on while they hold a display-sleep
    /// assertion (i.e. while playing video). Persisted by bundle ID so the
    /// choice survives restarts even when the app isn't running.
    @Published public var assertionAllowlist: [AssertingApp] = []

    private var clients: [UUID: WebOSClient] = [:]
    private var powerMonitor: PowerEventMonitor?
    private var idleMonitor: UserIdleMonitor?
    private var displayMonitor: DisplayConfigurationMonitor?
    private var mediaKeyMonitor: MediaKeyMonitor?
    private var keepaliveTimer: Timer?

    private let userDefaults = UserDefaults.standard
    private let devicesKey = "lgtvcompanion.devices"
    private let settingsKey = "lgtvcompanion.settings"

    /// WoL packets right after wake often get lost (network interface still
    /// coming up) — send several with a delay between.
    private static let wakeRetryCount = 5
    private static let wakeRetryDelayNs: UInt64 = 2_000_000_000 // 2s

    public init() {
        loadDevices()
        loadSettings()
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
            clients[device.id]?.disconnect()
            clients.removeValue(forKey: device.id)
        }
    }

    public func removeDevice(_ device: WebOSDevice) {
        devices.removeAll { $0.id == device.id }
        clients[device.id]?.disconnect()
        clients.removeValue(forKey: device.id)
        saveDevices()
    }

    public func getClient(for device: WebOSDevice) -> WebOSClient {
        if let client = clients[device.id] {
            return client
        }

        let client = WebOSClient(device: device)
        // Persist new/updated pairing keys so the TV doesn't prompt again
        // on every connection (previously the key was written to a separate
        // UserDefaults key that was never read back).
        client.onPairingKeyUpdated = { [weak self] deviceId, key in
            DispatchQueue.main.async {
                self?.storePairingKey(key, for: deviceId)
            }
        }
        clients[device.id] = client
        return client
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
            if (try? await withConnectedClient(for: device) { client in
                try await client.screenOn()
            }) != nil {
                return
            }
        }

        // 2. Otherwise Wake-on-LAN, repeated — single packets right after
        //    system wake are frequently lost.
        var lastError: Error?
        for attempt in 0..<Self.wakeRetryCount {
            do {
                try await WakeOnLAN.wake(
                    macAddress: device.macAddress,
                    ipAddress: device.ipAddress,
                    method: method
                )
                lastError = nil
            } catch {
                lastError = error
            }
            if attempt < Self.wakeRetryCount - 1 {
                try await Task.sleep(nanoseconds: Self.wakeRetryDelayNs)
            }
        }
        if let lastError = lastError {
            throw lastError
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
    /// cached for reuse.
    private func withConnectedClient<T>(
        for device: WebOSDevice,
        _ operation: (WebOSClient) async throws -> T
    ) async throws -> T {
        let client = await MainActor.run { self.getClient(for: device) }

        if !client.isConnected {
            try await client.connect()
        }
        if !client.isPaired {
            try await client.register()
        }

        do {
            return try await operation(client)
        } catch {
            // Stale connection? Reconnect once and retry. Await the teardown
            // (disconnectAndWait) before reconnecting — a fire-and-forget
            // disconnect runs on the client's serial queue and would otherwise
            // race connect() and cancel the brand-new connection.
            await client.disconnectAndWait()
            try await client.connect()
            try await client.register()
            return try await operation(client)
        }
    }

    // MARK: - Live Status & Direct Controls (Menu Bar)

    /// Fetches power state + audio status and publishes it.
    public func refreshStatus(for device: WebOSDevice) async {
        var status = DeviceStatus()
        if let result = try? await withConnectedClient(for: device, { client -> DeviceStatus in
            let state = try await client.getPowerState()
            let audio = try? await client.getAudioStatus()
            return DeviceStatus(powerState: state, volume: audio?.volume, muted: audio?.muted)
        }) {
            status = result
        }
        let final = status
        await MainActor.run { self.deviceStatuses[device.id] = final }
    }

    public func refreshAllStatuses() async {
        // Snapshot the @Published devices array on the main thread. This runs
        // from a background Task (keepalive timer / warm-up), and enumerating
        // the array off-main while the UI mutates it on main is a data race.
        let snapshot = await MainActor.run { self.devices.filter { $0.enabled } }
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

    /// Reads the TV's current foreground input id (read-only). Used by the UI
    /// to capture which input the Mac is connected to (the "Detect" button).
    public func readForegroundInput(for device: WebOSDevice) async throws -> String? {
        try await withConnectedClient(for: device) { try await $0.getForegroundAppInfo() }
    }

    /// Full power-off, regardless of the useScreenOff setting.
    public func fullPowerOff(_ device: WebOSDevice) async throws {
        try await withConnectedClient(for: device) { try await $0.powerOff() }
        await MainActor.run { self.deviceStatuses[device.id] = DeviceStatus() }
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
            print("Test failed: \(error)")
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
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.refreshAllStatuses() }
        }
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
        let targets = await devicesShowingMacInput(managedDevices)
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
                  for: device, { try await $0.getForegroundAppInfo() }) else {
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

    /// Re-installs the event tap if media keys are enabled but the tap
    /// couldn't be created earlier (e.g. Accessibility permission was
    /// granted only after launch). Call this periodically / on UI focus.
    public func ensureMediaKeyTap() {
        guard mediaKeysEnabled else { return }
        if let monitor = mediaKeyMonitor, monitor.isUsingEventTap { return }
        if MediaKeyMonitor.hasAccessibilityPermission {
            startMediaKeyMonitoring()
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
        guard let device = devices.first(where: { $0.enabled }) else { return false }

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
                let step = await MainActor.run { () -> Int in
                    if self.pendingVolumeSteps > 0 { self.pendingVolumeSteps -= 1; return 1 }
                    if self.pendingVolumeSteps < 0 { self.pendingVolumeSteps += 1; return -1 }
                    return 0
                }
                if step == 0 { break }

                do {
                    try await self.withConnectedClient(for: device) { client in
                        if step > 0 { try await client.volumeUp() }
                        else { try await client.volumeDown() }
                    }
                } catch {
                    // TV unreachable — drop whatever is still queued; replaying
                    // stale key presses seconds later would be worse.
                    await MainActor.run { self.pendingVolumeSteps = 0 }
                    break
                }
            }

            // One status refresh after the burst, not one per key press.
            await self.publishAudioStatus(for: device)

            await MainActor.run {
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
    }

    /// Fetches volume/mute once and publishes it so the menu-bar slider follows.
    private func publishAudioStatus(for device: WebOSDevice) async {
        guard let audio = try? await withConnectedClient(for: device, { try await $0.getAudioStatus() }) else {
            return
        }
        await MainActor.run {
            var status = self.deviceStatuses[device.id] ?? DeviceStatus()
            status.volume = audio.volume
            status.muted = audio.muted
            if status.powerState == nil { status.powerState = "Active" }
            self.deviceStatuses[device.id] = status
        }
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

    // MARK: - Persistence

    private func saveDevices() {
        if let encoded = try? JSONEncoder().encode(devices) {
            userDefaults.set(encoded, forKey: devicesKey)
        }
    }

    private func loadDevices() {
        guard let data = userDefaults.data(forKey: devicesKey),
              let decoded = try? JSONDecoder().decode([WebOSDevice].self, from: data) else {
            return
        }
        devices = decoded
    }

    private func saveSettings() {
        let settings: [String: Any] = [
            "userIdleEnabled": userIdleEnabled,
            "userIdleTimeout": userIdleTimeout,
            "mediaKeysEnabled": mediaKeysEnabled,
            "assertionAllowlist": assertionAllowlist.map {
                ["bundleID": $0.bundleID, "name": $0.name]
            }
        ]
        userDefaults.set(settings, forKey: settingsKey)
    }

    private func loadSettings() {
        guard let settings = userDefaults.dictionary(forKey: settingsKey) else {
            return
        }

        userIdleEnabled = settings["userIdleEnabled"] as? Bool ?? false
        userIdleTimeout = settings["userIdleTimeout"] as? TimeInterval ?? 300
        mediaKeysEnabled = settings["mediaKeysEnabled"] as? Bool ?? false

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
