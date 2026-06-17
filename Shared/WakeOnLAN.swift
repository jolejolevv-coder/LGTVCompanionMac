//
//  WakeOnLAN.swift
//  LGTV Companion Shared
//
//  Handles Wake-on-LAN magic packet sending
//

import Foundation
import Network

public enum WakeOnLANMethod: String, Codable, CaseIterable {
    case broadcast = "Broadcast"
    case targetIP = "Target IP Address"
    case subnet = "Subnet Directed Broadcast"

    public var description: String {
        switch self {
        case .broadcast:
            return "Send to 255.255.255.255 (most compatible)"
        case .targetIP:
            return "Send directly to TV IP address"
        case .subnet:
            return "Send to subnet broadcast address"
        }
    }
}

public class WakeOnLAN {

    /// Send a Wake-on-LAN magic packet to the specified MAC address
    /// - Parameters:
    ///   - macAddress: MAC address in format "AA:BB:CC:DD:EE:FF" or "AA-BB-CC-DD-EE-FF"
    ///   - ipAddress: IP address of the device (used for targetIP method)
    ///   - method: Wake-on-LAN method to use
    /// - Returns: True if packet was sent successfully
    @discardableResult
    public static func wake(macAddress: String, ipAddress: String, method: WakeOnLANMethod = .broadcast) async throws -> Bool {
        // Parse MAC address
        let macBytes = try parseMacAddress(macAddress)
        
        // Create magic packet
        let magicPacket = createMagicPacket(macBytes: macBytes)
        
        // Determine target address based on method
        let targetAddress: String
        switch method {
        case .broadcast:
            targetAddress = "255.255.255.255"
        case .targetIP:
            targetAddress = ipAddress
        case .subnet:
            targetAddress = try getSubnetBroadcast(for: ipAddress)
        }
        
        // Send the packet
        return try await sendUDPPacket(magicPacket, to: targetAddress, port: 9)
    }
    
    /// Parse MAC address string into bytes
    private static func parseMacAddress(_ mac: String) throws -> [UInt8] {
        let cleaned = mac.replacingOccurrences(of: ":", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .uppercased()
        
        guard cleaned.count == 12 else {
            throw NSError(domain: "Invalid MAC address format", code: -1)
        }
        
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: 12, by: 2) {
            let start = cleaned.index(cleaned.startIndex, offsetBy: i)
            let end = cleaned.index(start, offsetBy: 2)
            let byteString = String(cleaned[start..<end])
            
            guard let byte = UInt8(byteString, radix: 16) else {
                throw NSError(domain: "Invalid MAC address format", code: -1)
            }
            bytes.append(byte)
        }
        
        return bytes
    }
    
    /// Create a Wake-on-LAN magic packet
    /// The magic packet consists of:
    /// - 6 bytes of 0xFF
    /// - 16 repetitions of the target MAC address
    private static func createMagicPacket(macBytes: [UInt8]) -> Data {
        var packet = Data()
        
        // Add 6 bytes of 0xFF
        packet.append(contentsOf: [UInt8](repeating: 0xFF, count: 6))
        
        // Repeat MAC address 16 times
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        
        return packet
    }
    
    /// Send UDP packet to specified address and port.
    ///
    /// Uses a BSD socket with SO_BROADCAST: Network.framework's NWConnection
    /// cannot reliably send to 255.255.255.255 / subnet broadcast addresses,
    /// which made the (default) broadcast method silently fail.
    private static func sendUDPPacket(_ data: Data, to address: String, port: UInt16) async throws -> Bool {
        try await Task.detached(priority: .userInitiated) {
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                              userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
            }
            defer { close(fd) }

            var broadcastEnable: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST,
                       &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            guard inet_pton(AF_INET, address, &addr.sin_addr) == 1 else {
                throw NSError(domain: "WakeOnLAN", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid target address: \(address)"])
            }

            let sent = data.withUnsafeBytes { rawBuffer -> Int in
                withUnsafePointer(to: &addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        sendto(fd, rawBuffer.baseAddress, data.count, 0,
                               sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            guard sent == data.count else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                              userInfo: [NSLocalizedDescriptionKey: "Failed to send magic packet"])
            }
            return true
        }.value
    }
    
    /// Calculate subnet broadcast address from IP
    private static func getSubnetBroadcast(for ipAddress: String) throws -> String {
        // For simplicity, assume /24 subnet (most common)
        let components = ipAddress.split(separator: ".")
        guard components.count == 4 else {
            throw NSError(domain: "Invalid IP address", code: -1)
        }
        
        return "\(components[0]).\(components[1]).\(components[2]).255"
    }
    
    /// Validate MAC address format
    public static func isValidMacAddress(_ mac: String) -> Bool {
        let pattern = "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(mac.startIndex..., in: mac)
        return regex?.firstMatch(in: mac, range: range) != nil
    }
    
    /// Validate IP address format
    public static func isValidIPAddress(_ ip: String) -> Bool {
        let components = ip.split(separator: ".")
        guard components.count == 4 else { return false }
        
        return components.allSatisfy { component in
            guard let num = Int(component), num >= 0, num <= 255 else {
                return false
            }
            return true
        }
    }
}
