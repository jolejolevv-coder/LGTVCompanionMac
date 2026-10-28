import XCTest
@testable import LGTVCompanionShared

final class SSDPResponseTests: XCTestCase {

    private func response(_ lines: [String]) -> String {
        lines.joined(separator: "\r\n") + "\r\n\r\n"
    }

    /// Shape of an answer from an LG webOS TV.
    private let tvAnswer = [
        "HTTP/1.1 200 OK",
        "CACHE-CONTROL: max-age=1800",
        "EXT:",
        "LOCATION: http://192.168.178.50:1111/lg-tv.xml",
        "SERVER: Linux/4.4 UPnP/1.0 webOS/5.0 LGE WebOS TV",
        "ST: urn:lge-com:service:webos-second-screen:1",
        "USN: uuid:0c4a8f4e-1234-4abc-9def-001122334455::urn:lge-com:service:webos-second-screen:1",
    ]

    func testReadsLocationUSNAndServer() {
        let parsed = SSDPResponse.parse(response(tvAnswer))
        XCTAssertEqual(parsed.location, "http://192.168.178.50:1111/lg-tv.xml")
        XCTAssertEqual(parsed.usn,
                       "uuid:0c4a8f4e-1234-4abc-9def-001122334455::urn:lge-com:service:webos-second-screen:1")
        XCTAssertEqual(parsed.server, "Linux/4.4 UPnP/1.0 webOS/5.0 LGE WebOS TV")
        XCTAssertTrue(parsed.isFromLGWebOS)
    }

    func testHeaderNamesAreCaseInsensitive() {
        let parsed = SSDPResponse.parse(response([
            "HTTP/1.1 200 OK",
            "Location: http://10.0.0.5:1111/desc.xml",
            "usn: uuid:abc",
            "Server: webOS/4.0",
        ]))
        XCTAssertEqual(parsed.location, "http://10.0.0.5:1111/desc.xml")
        XCTAssertEqual(parsed.usn, "uuid:abc")
        XCTAssertEqual(parsed.server, "webOS/4.0")
    }

    func testValuesAreTrimmedAndKeepTheirColons() {
        let parsed = SSDPResponse.parse(response(["HTTP/1.1 200 OK", "LOCATION:   http://10.0.0.5:1111/d.xml   ", "SERVER: webOS"]))
        XCTAssertEqual(parsed.location, "http://10.0.0.5:1111/d.xml")
    }

    func testFirstOccurrenceOfAHeaderWins() {
        let parsed = SSDPResponse.parse(response([
            "HTTP/1.1 200 OK", "LOCATION: http://first/", "LOCATION: http://second/", "SERVER: webOS",
        ]))
        XCTAssertEqual(parsed.location, "http://first/")
    }

    func testMissingHeadersAreNil() {
        let parsed = SSDPResponse.parse(response(["HTTP/1.1 200 OK", "SERVER: webOS"]))
        XCTAssertNil(parsed.location)
        XCTAssertNil(parsed.usn)
        XCTAssertEqual(parsed.server, "webOS")
    }

    func testOtherUPnPDevicesAreNotLGWebOS() {
        let router = SSDPResponse.parse(response([
            "HTTP/1.1 200 OK",
            "LOCATION: http://192.168.178.1:49000/igddesc.xml",
            "SERVER: Linux UPnP/1.0 FRITZ!Box 7590",
            "USN: uuid:router::upnp:rootdevice",
        ]))
        XCTAssertFalse(router.isFromLGWebOS)
    }

    func testLGMarkersAreMatchedInAnyCase() {
        for marker in ["WEBOS", "LG Electronics", "lge"] {
            let parsed = SSDPResponse.parse(response(["HTTP/1.1 200 OK", "SERVER: Linux \(marker)"]))
            XCTAssertTrue(parsed.isFromLGWebOS, marker)
        }
    }

    func testEmptyInputYieldsNothing() {
        let parsed = SSDPResponse.parse("")
        XCTAssertNil(parsed.location)
        XCTAssertNil(parsed.usn)
        XCTAssertNil(parsed.server)
        XCTAssertFalse(parsed.isFromLGWebOS)
    }
}
