import XCTest
@testable import LGTVCompanionShared

/// Smoke tests for the pieces that run callbacks from timers, run loop
/// sources and system registrations. They start and stop each piece for a
/// short moment under Swift 6 isolation checking: a callback that enters the
/// main actor from the wrong queue would trap here instead of overnight.
///
/// Not covered, because they need a permission, Bluetooth or a TV: the media
/// key event tap (Accessibility), CoreBluetooth in the speaker controller,
/// WebOSClient connect, and the Core Audio tap of the software volume.
@MainActor
final class BackgroundMonitorSmokeTests: XCTestCase {

    private static let observeSeconds: TimeInterval = 1.5

    /// Lets the main run loop run, so timers and queued blocks can fire.
    private func spinMainRunLoop(for seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    func testIdleMonitorTimerFiresOnMainActor() async {
        // Threshold 0: the first check, one second after start, reports idle.
        let monitor = UserIdleMonitor(idleThreshold: 0)
        let reported = expectation(description: "idle state reported")
        monitor.onIdleStateChanged = { isIdle in
            if isIdle { reported.fulfill() }
        }
        monitor.startMonitoring()
        await fulfillment(of: [reported], timeout: 5)
        monitor.stopMonitoring()
    }

    func testIdleMonitorStopsCleanly() async {
        let monitor = UserIdleMonitor(idleThreshold: 3600)
        monitor.startMonitoring()
        await spinMainRunLoop(for: Self.observeSeconds)
        monitor.stopMonitoring()
        await spinMainRunLoop(for: 0.2)
    }

    func testDisplayConfigurationMonitorRegistersAndDeregisters() async {
        var monitor: DisplayConfigurationMonitor? = DisplayConfigurationMonitor()
        monitor?.onDisplayConfigurationChanged = {}
        XCTAssertGreaterThan(monitor?.getActiveDisplayCount() ?? 0, 0)
        await spinMainRunLoop(for: Self.observeSeconds)
        monitor = nil
        await spinMainRunLoop(for: 0.2)
    }

    func testPowerEventMonitorRegistersAndDeregisters() async {
        var monitor: PowerEventMonitor? = PowerEventMonitor()
        monitor?.onPowerEvent = { _, completion in completion() }
        await spinMainRunLoop(for: Self.observeSeconds)
        monitor = nil
        await spinMainRunLoop(for: 0.2)
    }

    func testSpeakerAutomationTimerLivesAndDiesWithTheObject() async {
        let suite = "lgtvcompanion.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var automation: SpeakerAutomation? = SpeakerAutomation(
            speakers: EdifierSpeakerController(), defaults: defaults,
            clock: { Date(timeIntervalSince1970: 0) })
        XCTAssertNotNil(automation)
        await spinMainRunLoop(for: Self.observeSeconds)
        automation = nil
        await spinMainRunLoop(for: 0.2)
    }

    func testSoftwareVolumeControllerConstructsAndTearsDownWithoutTap() async {
        var controller: SoftwareVolumeController? = SoftwareVolumeController()
        controller?.onOutputDeviceChanged = {}
        await spinMainRunLoop(for: Self.observeSeconds)
        controller = nil
        await spinMainRunLoop(for: 0.2)
    }
}
