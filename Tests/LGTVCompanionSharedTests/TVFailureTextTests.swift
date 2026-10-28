import XCTest
@testable import LGTVCompanionShared

final class TVFailureTextTests: XCTestCase {

    func testUnreachableTVNamesTheTVAndTheFix() {
        for error in [WebOSError.timeout, .notConnected, .networkError(URLError(.cannotConnectToHost))] {
            let text = TVFailureText.message(for: error, tvName: "LG OLED")
            XCTAssertEqual(text, "Unable to reach LG OLED. Check that the TV is on and on the same network.")
        }
    }

    func testPairingProblemsPointToPairing() {
        XCTAssertTrue(TVFailureText.message(for: WebOSError.pairingRequired, tvName: "TV").contains("pair"))
        XCTAssertTrue(TVFailureText.message(for: WebOSError.pairingRejected, tvName: "TV").contains("accept"))
    }

    func testRefusedCommandKeepsTheReason() {
        let text = TVFailureText.message(for: WebOSError.commandFailed("403 insufficient permissions"), tvName: "TV")
        XCTAssertTrue(text.contains("403 insufficient permissions"))
    }

    func testUnknownErrorFallsBackToItsDescription() {
        struct Odd: LocalizedError { var errorDescription: String? { "odd" } }
        XCTAssertEqual(TVFailureText.message(for: Odd(), tvName: "TV"), "TV: odd")
    }
}
