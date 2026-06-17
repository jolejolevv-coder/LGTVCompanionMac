//
//  DeviceDiscovery.swift
//  LGTV Companion Shared
//
//  Discovers LG WebOS devices on the local network using SSDP
//

import Foundation
import Network

public struct DiscoveredDevice {
    public let ipAddress: String
    public let friendlyName: String
    public let modelName: String
    public let macAddress: String?

    public init(ipAddress: String, friendlyName: String, modelName: String, macAddress: String?) {
        self.ipAddress = ipAddress
        self.friendlyName = friendlyName
        self.modelName = modelName
        self.macAddress = macAddress
    }

    public var displayName: String {
        if friendlyName.isEmpty {
            return modelName.isEmpty ? ipAddress : modelName
        }
        return friendlyName
    }
}

public class DeviceDiscovery: ObservableObject {
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var isScanning = false

    public init() {}

    private var group: NWConnectionGroup?
    private var scanTimer: Timer?

    /// Search targets: dedicated webOS second-screen service, plus generic
    /// rootdevice as fallback for TVs that don't answer the specific ST.
    private static let searchTargets = [
        "urn:lge-com:service:webos-second-screen:1",
        "upnp:rootdevice"
    ]

    /// Start scanning for LG WebOS devices
    public func startScan(timeout: TimeInterval = 8.0) {
        guard !isScanning else { return }

        isScanning = true
        discoveredDevices.removeAll()

        // FIX: the previous implementation sent the M-SEARCH on one
        // connection and listened on a *separate* NWListener bound to port
        // 1900. SSDP responses are unicast back to the *source port* of the
        // M-SEARCH, so that listener never received anything. Using an
        // NWConnectionGroup joined to the SSDP multicast group sends and
        // receives on the same socket.
        do {
            let multicast = try NWMulticastGroup(for: [
                .hostPort(host: "239.255.255.250", port: 1900)
            ])
            let group = NWConnectionGroup(with: multicast, using: .udp)
            self.group = group

            group.setReceiveHandler(maximumMessageSize: 16384, rejectOversizedMessages: true) { [weak self] message, data, _ in
                guard let self = self, let data = data, !data.isEmpty else { return }
                self.parseSSDPResponse(data, from: message.remoteEndpoint)
            }

            group.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.sendSSDPSearch()
                case .failed(let error):
                    print("SSDP group failed: \(error)")
                    DispatchQueue.main.async { self?.stopScan() }
                default:
                    break
                }
            }

            group.start(queue: .main)
        } catch {
            print("Failed to join SSDP multicast group: \(error)")
            isScanning = false
            return
        }

        // Stop scanning after timeout
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.stopScan()
        }
    }

    /// Stop scanning
    public func stopScan() {
        isScanning = false
        scanTimer?.invalidate()
        scanTimer = nil
        group?.cancel()
        group = nil
    }

    /// Send SSDP M-SEARCH multicast requests (repeated — UDP multicast is
    /// lossy, sending each search twice is standard practice).
    private func sendSSDPSearch() {
        guard let group = group else { return }

        for target in Self.searchTargets {
            let ssdpMessage = [
                "M-SEARCH * HTTP/1.1",
                "HOST: 239.255.255.250:1900",
                "MAN: \"ssdp:discover\"",
                "MX: 3",
                "ST: \(target)",
                "", ""
            ].joined(separator: "\r\n")

            guard let data = ssdpMessage.data(using: .utf8) else { continue }

            group.send(content: data) { error in
                if let error = error {
                    print("SSDP send failed: \(error)")
                }
            }
            // Repeat after 1s for reliability
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.group?.send(content: data) { _ in }
            }
        }
    }

    /// Parse SSDP response and extract device information
    private func parseSSDPResponse(_ data: Data, from endpoint: NWEndpoint?) {
        guard let response = String(data: data, encoding: .utf8) else { return }

        // Only handle search responses / announcements from LG WebOS devices
        let lowercased = response.lowercased()
        guard lowercased.contains("webos") || lowercased.contains("lg electronics")
                || lowercased.contains("lge") else { return }

        // Extract IP address from the response's source endpoint
        var ipAddress = ""
        if case .hostPort(let host, _)? = endpoint {
            // Strip IPv6 scope suffix ("%en0") if present
            ipAddress = "\(host)".components(separatedBy: "%").first ?? "\(host)"
        }

        // Extract LOCATION header to get device description URL
        var locationURL: String?
        for line in response.components(separatedBy: "\r\n") {
            if line.uppercased().hasPrefix("LOCATION:") {
                locationURL = String(line.dropFirst("LOCATION:".count))
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }

        if let urlString = locationURL, let url = URL(string: urlString) {
            // Prefer the IP from the LOCATION URL if we couldn't resolve one
            if ipAddress.isEmpty, let host = url.host {
                ipAddress = host
            }
            fetchDeviceDescription(from: url, ipAddress: ipAddress)
        } else if !ipAddress.isEmpty {
            // Add device with limited info
            DispatchQueue.main.async {
                self.addDeviceIfNew(DiscoveredDevice(
                    ipAddress: ipAddress,
                    friendlyName: "",
                    modelName: "LG WebOS TV",
                    macAddress: nil
                ))
            }
        }
    }

    /// Fetch and parse device description XML
    private func fetchDeviceDescription(from url: URL, ipAddress: String) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            guard let data = data, error == nil else {
                // Description fetch failed — still record the device
                DispatchQueue.main.async {
                    self.addDeviceIfNew(DiscoveredDevice(
                        ipAddress: ipAddress,
                        friendlyName: "",
                        modelName: "LG WebOS TV",
                        macAddress: nil
                    ))
                }
                return
            }

            let parser = DeviceDescriptionParser()
            parser.parse(data)

            DispatchQueue.main.async {
                self.addDeviceIfNew(DiscoveredDevice(
                    ipAddress: ipAddress,
                    friendlyName: parser.friendlyName,
                    modelName: parser.modelName,
                    macAddress: nil // MAC address typically not in SSDP
                ))
            }
        }.resume()
    }

    /// Add device to list if not already present (must run on main)
    private func addDeviceIfNew(_ device: DiscoveredDevice) {
        guard !device.ipAddress.isEmpty else { return }
        if !discoveredDevices.contains(where: { $0.ipAddress == device.ipAddress }) {
            discoveredDevices.append(device)
        } else if !device.friendlyName.isEmpty,
                  let index = discoveredDevices.firstIndex(where: {
                      $0.ipAddress == device.ipAddress && $0.friendlyName.isEmpty
                  }) {
            // Upgrade an entry that previously had no name
            discoveredDevices[index] = device
        }
    }
}

// MARK: - XML Parser for Device Description

class DeviceDescriptionParser: NSObject, XMLParserDelegate {
    var friendlyName = ""
    var modelName = ""

    private var currentElement = ""
    private var currentValue = ""

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "friendlyName" where friendlyName.isEmpty:
            friendlyName = value
        case "modelName" where modelName.isEmpty:
            modelName = value
        default:
            break
        }
    }
}
