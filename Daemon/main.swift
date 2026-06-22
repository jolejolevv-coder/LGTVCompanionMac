//
//  main.swift
//  LGTV Companion Daemon
//
//  Background daemon that monitors power events and controls devices
//

import LGTVCompanionShared
import Foundation

class Daemon {
    private let deviceManager = DeviceManager()
    private var isRunning = true
    private var signalSources: [DispatchSourceSignal] = []

    func run() {
        print("LGTV Companion Daemon starting...")

        // Start monitoring power events
        deviceManager.startPowerEventMonitoring()

        print("Power event monitoring started")
        print("Monitoring \(deviceManager.devices.count) device(s)")

        // Graceful shutdown via GCD signal sources. A raw signal() handler may
        // only call async-signal-safe functions — print()/exit() are not, and
        // can deadlock or corrupt the heap if the signal lands mid-allocation.
        // A DispatchSource handler runs on a normal thread, so it can log and
        // tear down safely.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN) // disable default termination; the source handles it
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                print("Received signal \(sig), shutting down...")
                self?.deviceManager.stopPowerEventMonitoring()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }

        // Keep running
        RunLoop.main.run()
    }
    
    deinit {
        deviceManager.stopPowerEventMonitoring()
        print("Daemon stopped")
    }
}

// Entry point
let daemon = Daemon()
daemon.run()
