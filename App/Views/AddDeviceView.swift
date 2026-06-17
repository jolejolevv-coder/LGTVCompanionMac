//
//  AddDeviceView.swift
//  LGTV Companion
//
//  View for manually adding a device
//

import LGTVCompanionShared
import SwiftUI

struct AddDeviceView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @Environment(\.dismiss) var dismiss
    
    @State private var name = "LG TV"
    @State private var ipAddress = ""
    @State private var macAddress = ""
    
    var isValid: Bool {
        !name.isEmpty &&
        WakeOnLAN.isValidIPAddress(ipAddress) &&
        WakeOnLAN.isValidMacAddress(macAddress)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Device Manually")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter the network information for your LG WebOS TV")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section {
                    TextField("Device Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("IP Address", text: $ipAddress)
                        .textFieldStyle(.roundedBorder)
                        .help("Static IP address of your TV (e.g., 192.168.1.100)")
                    
                    if !ipAddress.isEmpty && !WakeOnLAN.isValidIPAddress(ipAddress) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Invalid IP address format")
                                .font(.caption)
                        }
                    }
                    
                    TextField("MAC Address", text: $macAddress)
                        .textFieldStyle(.roundedBorder)
                        .help("MAC address in format AA:BB:CC:DD:EE:FF")
                    
                    if !macAddress.isEmpty && !WakeOnLAN.isValidMacAddress(macAddress) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Invalid MAC address format")
                                .font(.caption)
                        }
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to find this information:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Turn on your TV")
                            Text("2. Go to Settings → All Settings → Connection → Network")
                            Text("3. Select 'Wired Connection (Ethernet)' or 'Wi-Fi Connection'")
                            Text("4. View the 'IP Address' and 'MAC Address'")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Help")
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Add Device") {
                    addDevice()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
    }
    
    private func addDevice() {
        let device = WebOSDevice(
            name: name,
            ipAddress: ipAddress,
            macAddress: macAddress
        )
        
        deviceManager.addDevice(device)
        dismiss()
    }
}
