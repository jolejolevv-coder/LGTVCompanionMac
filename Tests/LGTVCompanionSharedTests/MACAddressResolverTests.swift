import XCTest
@testable import LGTVCompanionShared

final class MACAddressResolverTests: XCTestCase {

    // MARK: normalize

    func testNormalizeUppercasesAndKeepsFullOctets() {
        XCTAssertEqual(MACAddressResolver.normalize("80:5b:65:d6:27:e0"), "80:5B:65:D6:27:E0")
    }

    func testNormalizeRestoresLeadingZerosDroppedByArp() {
        XCTAssertEqual(MACAddressResolver.normalize("0:1b:c:d6:7:e0"), "00:1B:0C:D6:07:E0")
    }

    func testNormalizeRejectsIncompleteMarker() {
        XCTAssertNil(MACAddressResolver.normalize("(incomplete)"))
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

    // MARK: parse

    func testParseReadsMacFromArpLine() {
        let output = "? (192.168.178.25) at 80:5b:65:d6:27:e0 on en0 ifscope [ethernet]\n"
        XCTAssertEqual(MACAddressResolver.parse(arpOutput: output, ip: "192.168.178.25"), "80:5B:65:D6:27:E0")
    }

    func testParseHandlesTwoInterfacesForTheSameHost() {
        let output = """
        ? (192.168.178.25) at 80:5b:65:d6:27:e0 on en0 ifscope [ethernet]
        ? (192.168.178.25) at 80:5b:65:d6:27:e0 on en1 ifscope [ethernet]
        """
        XCTAssertEqual(MACAddressResolver.parse(arpOutput: output, ip: "192.168.178.25"), "80:5B:65:D6:27:E0")
    }

    func testParseSkipsIncompleteEntryAndUsesTheAnsweredOne() {
        let output = """
        ? (192.168.178.25) at (incomplete) on en1 ifscope [ethernet]
        ? (192.168.178.25) at 80:5b:65:d6:27:e0 on en0 ifscope [ethernet]
        """
        XCTAssertEqual(MACAddressResolver.parse(arpOutput: output, ip: "192.168.178.25"), "80:5B:65:D6:27:E0")
    }

    func testParseReturnsNilWhenHostIsUnknown() {
        XCTAssertNil(MACAddressResolver.parse(arpOutput: "192.168.178.99 (192.168.178.99) -- no entry\n",
                                              ip: "192.168.178.99"))
        XCTAssertNil(MACAddressResolver.parse(arpOutput: "", ip: "192.168.178.25"))
    }

    func testParseDoesNotMatchAnAddressThatOnlySharesAPrefix() {
        // Asking for .2 must not pick up the line for .25.
        let output = "? (192.168.178.25) at 80:5b:65:d6:27:e0 on en0 ifscope [ethernet]\n"
        XCTAssertNil(MACAddressResolver.parse(arpOutput: output, ip: "192.168.178.2"))
    }

    // MARK: lookup guards

    func testLookupRejectsMalformedIpWithoutRunningArp() {
        XCTAssertNil(MACAddressResolver.lookup(ip: "not an ip"))
        XCTAssertNil(MACAddressResolver.lookup(ip: "192.168.178.25; rm"))
    }
}
