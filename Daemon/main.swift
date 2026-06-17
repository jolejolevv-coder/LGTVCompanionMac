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
    
    func run() {
        print("LGTV Companion Daemon starting...")
        
        // Start monitoring power events
        deviceManager.startPowerEventMonitoring()
        
        print("Power event monitoring started")
        print("Monitoring \(deviceManager.devices.count) device(s)")
        
        // Set up signal handlers for graceful shutdown
        signal(SIGTERM) { _ in
            print("Received SIGTERM, shutting down...")
            exit(0)
        }
        
        signal(SIGINT) { _ in
            print("Received SIGINT, shutting down...")
            exit(0)
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
