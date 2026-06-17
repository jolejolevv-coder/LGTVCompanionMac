//
//  DeviceScannerView.swift
//  LGTV Companion
//
//  View for scanning and discovering devices on the network
//

import LGTVCompanionShared
import SwiftUI

struct DeviceScannerView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var discovery = DeviceDiscovery()
    @State private var selectedDevices: Set<DiscoveredDevice.ID> = []
    @State private var macAddresses: [String: String] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            if discovery.isScanning {
                scanningView
            } else if discovery.discoveredDevices.isEmpty {
                emptyStateView
            } else {
                deviceListView
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 600, height: 500)
        .onAppear {
            discovery.startScan()
        }
    }
    
    // MARK: - Views
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan for Devices")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Searching for LG WebOS devices on your network...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    
    private var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Scanning...")
                .font(.headline)
            
            Text("This may take a few seconds")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No devices found")
                .font(.headline)
            
            Text("Make sure your TV is turned on and connected to the same network as your Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Scan Again") {
                discovery.startScan()
            }
            .padding(.top, 8)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var deviceListView: some View {
        List(selection: $selectedDevices) {
            ForEach(discovery.discoveredDevices, id: \.ipAddress) { device in
                DiscoveredDeviceRow(
                    device: device,
                    macAddress: Binding(
                        get: { macAddresses[device.ipAddress] ?? "" },
                        set: { macAddresses[device.ipAddress] = $0 }
                    )
                )
                .tag(device.ipAddress)
            }
        }
        .listStyle(.inset)
    }
    
    private var footerView: some View {
        HStack {
            Button("Scan Again") {
                discovery.startScan()
            }
            .disabled(discovery.isScanning)
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Button("Add Selected") {
                addSelectedDevices()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedDevices.isEmpty)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func addSelectedDevices() {
        for deviceIP in selectedDevices {
            guard let discoveredDevice = discovery.discoveredDevices.first(where: { $0.ipAddress == deviceIP }),
                  let macAddress = macAddresses[deviceIP],
                  !macAddress.isEmpty,
                  WakeOnLAN.isValidMacAddress(macAddress) else {
                continue
            }
            
            let device = WebOSDevice(
                name: discoveredDevice.displayName,
                ipAddress: discoveredDevice.ipAddress,
                macAddress: macAddress
            )
            
            deviceManager.addDevice(device)
        }
        
        dismiss()
    }
}

// MARK: - Discovered Device Row

struct DiscoveredDeviceRow: View {
    let device: DiscoveredDevice
    @Binding var macAddress: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tv")
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.headline)
                    
                    Text(device.ipAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            HStack {
                Text("MAC Address:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("AA:BB:CC:DD:EE:FF", text: $macAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                
                if !macAddress.isEmpty {
                    Image(systemName: WakeOnLAN.isValidMacAddress(macAddress) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(WakeOnLAN.isValidMacAddress(macAddress) ? .green : .red)
                }
            }
            
            Text("Note: MAC address must be entered manually. You can find it in your TV's network settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(.vertical, 8)
    }
}

extension DiscoveredDevice: Identifiable {
    public var id: String { ipAddress }
}
