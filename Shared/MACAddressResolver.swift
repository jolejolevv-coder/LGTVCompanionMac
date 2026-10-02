//
//  MACAddressResolver.swift
//  LGTV Companion Shared
//
//  Finds a device's MAC address from its IP, so the user does not have to
//  copy it from the TV's network settings. Wake-on-LAN needs the MAC.
//
//  The Mac already knows the MAC of every host on the local network it has
//  talked to: it is in the ARP table. We read it from there.
//
//  macOS only shows ARP entries to processes that hold the Local Network
//  permission. The app has it (it needs it to reach the TV at all); a process
//  without it gets "no entry" for every host, which reads as "not found".
//

import Foundation
import Network

public enum MACAddressResolver {
    private static let arpPath = "/usr/sbin/arp"
    /// webOS control port. Connecting to it makes the Mac resolve the TV's
    /// MAC, which fills the ARP table. Whether the port answers is irrelevant.
    private static let pokePort: UInt16 = 3001
    private static let pokeTimeout: TimeInterval = 1.5
    private static let octetCount = 6

    /// Contacts the host once so the ARP table has an entry, then looks the
    /// MAC up. Returns nil if the host is off, not on the local network, or
    /// the IP is malformed.
    public static func resolve(ip: String) async -> String? {
        guard WakeOnLAN.isValidIPAddress(ip) else { return nil }
        await poke(ip: ip)
        return lookup(ip: ip)
    }

    /// Reads the ARP table only. Use when the host was contacted just before.
    /// Blocks for a few milliseconds; do not call on the main thread.
    public static func lookup(ip: String) -> String? {
        guard WakeOnLAN.isValidIPAddress(ip) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: arpPath)
        process.arguments = ["-n", ip]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return parse(arpOutput: String(decoding: data, as: UTF8.self), ip: ip)
    }

    /// Extracts the MAC for `ip` from `arp -n` output, for example
    /// `? (192.168.178.25) at 80:5b:65:d6:27:e0 on en0 ifscope [ethernet]`.
    /// Entries without an answer read `at (incomplete)` and yield nil.
    static func parse(arpOutput: String, ip: String) -> String? {
        for line in arpOutput.split(separator: "\n") {
            guard line.contains("(\(ip))") else { continue }
            let words = line.split(separator: " ")
            guard let atIndex = words.firstIndex(of: "at"), atIndex + 1 < words.count,
                  let mac = normalize(String(words[atIndex + 1])) else { continue }
            return mac
        }
        return nil
    }

    /// `arp` drops leading zeros ("0:1b:c:…"). Returns the canonical form
    /// "00:1B:0C:…", or nil if the text is not six hex octets or is a
    /// placeholder address.
    static func normalize(_ raw: String) -> String? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == octetCount else { return nil }

        var octets: [String] = []
        for part in parts {
            guard (1...2).contains(part.count), let value = UInt8(part, radix: 16) else { return nil }
            octets.append(String(format: "%02X", value))
        }

        let mac = octets.joined(separator: ":")
        // All zeros / all ones are "unknown" and "broadcast", never a device.
        if mac == "00:00:00:00:00:00" || mac == "FF:FF:FF:FF:FF:FF" { return nil }
        return mac
    }

    /// Opens a TCP connection and waits until it settles or times out.
    private static func poke(ip: String) async {
        guard let port = NWEndpoint.Port(rawValue: pokePort) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: port, using: .tcp)
        let queue = DispatchQueue(label: "com.lgtvcompanion.macresolver")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeGuard()
            @Sendable func finish() {
                guard once.tryClaim() else { return }
                connection.cancel()
                continuation.resume()
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled: finish()
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + pokeTimeout) { finish() }
        }
    }
}
