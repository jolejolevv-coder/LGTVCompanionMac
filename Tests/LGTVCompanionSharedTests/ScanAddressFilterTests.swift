import XCTest
@testable import LGTVCompanionShared

final class ScanAddressFilterTests: XCTestCase {

    func testEachAddressIsHandledOncePerScan() {
        var filter = ScanAddressFilter()

        XCTAssertTrue(filter.isFirstSighting(of: "192.168.178.25"))
        XCTAssertFalse(filter.isFirstSighting(of: "192.168.178.25"))
        XCTAssertTrue(filter.isFirstSighting(of: "192.168.178.26"))
    }

    func testResetStartsANewScan() {
        var filter = ScanAddressFilter()
        _ = filter.isFirstSighting(of: "192.168.178.25")

        filter.reset()

        XCTAssertTrue(filter.isFirstSighting(of: "192.168.178.25"))
    }
}
