import XCTest
@testable import LGTVCompanionShared

final class MACAddressResolverTests: XCTestCase {

    /// Answer of an LG OLED42C2 to a unicast DIAL search, captured 2026-10-02.
    private let dialAnswer = [
        "HTTP/1.1 200 OK",
        "Location: http://192.168.178.25:2024/",
        "Cache-Control: max-age=1800",
        "Server: WebOS/1.5 UPnP/1.0 webOSTV/1.0",
        "EXT: ",
        "USN: uuid:fccc37b5-62b7-4848-8e7f-648661607324::urn:dial-multiscreen-org:service:dial:1",
        "ST: urn:dial-multiscreen-org:service:dial:1",
        "Date: Fri, 02 Oct 2026 19:35:20 GMT",
        "WAKEUP: MAC=80:5b:65:d6:27:e0;Timeout=60",
        "", ""
    ].joined(separator: "\r\n")

    // MARK: parse

    func testParseReadsMacFromRealDialAnswer() {
        XCTAssertEqual(MACAddressResolver.parse(ssdpResponse: dialAnswer), "80:5B:65:D6:27:E0")
    }

    func testParseIgnoresHeaderCaseAndFieldOrder() {
        let answer = "HTTP/1.1 200 OK\r\nwakeup: Timeout=60; mac=80:5B:65:D6:27:E0\r\n\r\n"
        XCTAssertEqual(MACAddressResolver.parse(ssdpResponse: answer), "80:5B:65:D6:27:E0")
    }

    func testParseReturnsNilWithoutWakeupHeader() {
        let answer = "HTTP/1.1 200 OK\r\nST: urn:lge-com:service:webos-second-screen:1\r\n\r\n"
        XCTAssertNil(MACAddressResolver.parse(ssdpResponse: answer))
        XCTAssertNil(MACAddressResolver.parse(ssdpResponse: ""))
    }

    func testParseReturnsNilForWakeupHeaderWithoutUsableMac() {
        XCTAssertNil(MACAddressResolver.parse(ssdpResponse: "WAKEUP: Timeout=60\r\n"))
        XCTAssertNil(MACAddressResolver.parse(ssdpResponse: "WAKEUP: MAC=garbage;Timeout=60\r\n"))
        XCTAssertNil(MACAddressResolver.parse(ssdpResponse: "WAKEUP: MAC=00:00:00:00:00:00\r\n"))
    }

    func testParseDoesNotMistakeOtherHeadersForTheMac() {
        // A MAC-looking value elsewhere must not be picked up.
        let answer = "HTTP/1.1 200 OK\r\nUSN: uuid:80:5b:65:d6:27:e0\r\n\r\n"
        XCTAssertNil(MACAddressResolver.parse(ssdpResponse: answer))
    }

    // MARK: normalize

    func testNormalizeUppercasesAndKeepsFullOctets() {
        XCTAssertEqual(MACAddressResolver.normalize("80:5b:65:d6:27:e0"), "80:5B:65:D6:27:E0")
    }

    func testNormalizeAcceptsDashesAndRestoresLeadingZeros() {
        XCTAssertEqual(MACAddressResolver.normalize("80-5b-65-d6-27-e0"), "80:5B:65:D6:27:E0")
        XCTAssertEqual(MACAddressResolver.normalize("0:1b:c:d6:7:e0"), "00:1B:0C:D6:07:E0")
    }

    func testNormalizeRejectsWrongOctetCountAndBadHex() {
        XCTAssertNil(MACAddressResolver.normalize("80:5b:65:d6:27"))
        XCTAssertNil(MACAddressResolver.normalize("80:5b:65:d6:27:e0:11"))
        XCTAssertNil(MACAddressResolver.normalize("80:5b:65:d6:27:zz"))
        XCTAssertNil(MACAddressResolver.normalize("80:5b:65:d6:27:e00"))
        XCTAssertNil(MACAddressResolver.normalize("80:5b::d6:27:e0"))
    }

    func testNormalizeRejectsPlaceholderAddresses() {
        XCTAssertNil(MACAddressResolver.normalize("0:0:0:0:0:0"))
        XCTAssertNil(MACAddressResolver.normalize("ff:ff:ff:ff:ff:ff"))
    }

    func testNormalizedResultPassesTheAppsOwnValidation() throws {
        let mac = try XCTUnwrap(MACAddressResolver.normalize("0:1b:c:d6:7:e0"))
        XCTAssertTrue(WakeOnLAN.isValidMacAddress(mac))
    }

    // MARK: resolve guards

    func testResolveRejectsMalformedIpWithoutTouchingTheNetwork() async {
        let result = await MACAddressResolver.resolve(ip: "not an ip")
        XCTAssertNil(result)
    }
}
