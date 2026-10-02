//
//  MACAddressResolver.swift
//  LGTV Companion Shared
//
//  Finds a TV's MAC address from its IP, so the user does not have to copy it
//  from the TV's network settings. Wake-on-LAN needs the MAC.
//
//  The TV states it itself: its SSDP answer for the DIAL service carries
//  `WAKEUP: MAC=80:5b:65:d6:27:e0;Timeout=60`, the address to wake it on the
//  interface it is currently using. We ask the TV directly (unicast SSDP).
//
//  Reading the Mac's ARP table would be the generic way, but macOS hides ARP
//  entries from apps (Local Network privacy), even with the permission
//  granted: `arp` launched by the app reports "no entry" for every host.
//

import Foundation

public enum MACAddressResolver {
    private static let ssdpPort: UInt16 = 1900
    /// The only SSDP service whose answer includes the WAKEUP header.
    private static let searchTarget = "urn:dial-multiscreen-org:service:dial:1"
    private static let wakeupHeader = "WAKEUP:"
    /// How long to wait for the TV's answer. It normally arrives within
    /// 100 ms; UDP may drop a packet, hence the second attempt.
    private static let answerTimeoutSeconds = 1
    private static let attempts = 2
    private static let maxAnswerBytes = 4096
    private static let octetCount = 6

    /// Asks the device at `ip` for its Wake-on-LAN MAC address. Returns nil
    /// if the IP is malformed, the device is off, or it is not a TV that
    /// answers DIAL searches.
    public static func resolve(ip: String) async -> String? {
        guard WakeOnLAN.isValidIPAddress(ip) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            for _ in 0..<attempts {
                if let mac = askOnce(ip: ip) { return mac }
            }
            return nil
        }.value
    }

    /// Extracts the MAC from an SSDP answer's WAKEUP header, for example
    /// `WAKEUP: MAC=80:5b:65:d6:27:e0;Timeout=60`. Header names are
    /// case-insensitive.
    static func parse(ssdpResponse: String) -> String? {
        for rawLine in ssdpResponse.components(separatedBy: "\r\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.uppercased().hasPrefix(wakeupHeader) else { continue }
            for field in line.dropFirst(wakeupHeader.count).split(separator: ";") {
                let pair = field.trimmingCharacters(in: .whitespaces)
                guard pair.uppercased().hasPrefix("MAC=") else { continue }
                return normalize(String(pair.dropFirst("MAC=".count)))
            }
        }
        return nil
    }

    /// Returns the canonical form "00:1B:0C:…" for six hex octets separated
    /// by ":" or "-", tolerating dropped leading zeros. nil for anything else
    /// and for placeholder addresses.
    static func normalize(_ raw: String) -> String? {
        let parts = raw.trimmingCharacters(in: .whitespaces)
            .split(omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == "-" })
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

    /// One unicast M-SEARCH and one wait for the answer. Blocking; runs off
    /// the main thread. A plain UDP socket is used because the TV answers
    /// from a different source port, which a connected socket would drop.
    private static func askOnce(ip: String) -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeout = timeval(tv_sec: answerTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = ssdpPort.bigEndian
        guard inet_pton(AF_INET, ip, &address.sin_addr) == 1 else { return nil }

        let request = [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(ip):\(ssdpPort)",
            "MAN: \"ssdp:discover\"",
            "MX: 1",
            "ST: \(searchTarget)",
            "", ""
        ].joined(separator: "\r\n")
        let requestBytes = Array(request.utf8)

        let sent = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, requestBytes, requestBytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == requestBytes.count else { return nil }

        var buffer = [UInt8](repeating: 0, count: maxAnswerBytes)
        let received = recv(fd, &buffer, buffer.count, 0)
        guard received > 0 else { return nil }
        return parse(ssdpResponse: String(decoding: buffer[0..<received], as: UTF8.self))
    }
}
