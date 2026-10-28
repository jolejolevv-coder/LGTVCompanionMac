import XCTest
@testable import LGTVCompanionShared

final class VolumeKeyRouteTests: XCTestCase {

    private struct Row {
        let name: String
        let speakers: Bool
        let hasTV: Bool
        let software: Bool
        let tvCanAdjust: Bool?
        let expected: VolumeKeyRoute
    }

    private let rows: [Row] = [
        // Speakers win over everything else.
        Row(name: "speakers, no TV", speakers: true, hasTV: false, software: false, tvCanAdjust: nil, expected: .speakers),
        Row(name: "speakers, TV can adjust", speakers: true, hasTV: true, software: false, tvCanAdjust: true, expected: .speakers),
        Row(name: "speakers beat software volume", speakers: true, hasTV: true, software: true, tvCanAdjust: false, expected: .speakers),
        // Speakers unreachable: falls through to the TV rules.
        Row(name: "speakers down, TV can adjust", speakers: false, hasTV: true, software: false, tvCanAdjust: true, expected: .tv),
        // No enabled TV and no speakers: macOS keeps the keys.
        Row(name: "nothing enabled", speakers: false, hasTV: false, software: false, tvCanAdjust: nil, expected: .passThrough),
        Row(name: "no TV, stale software flag", speakers: false, hasTV: false, software: true, tvCanAdjust: false, expected: .passThrough),
        // Software volume is active (TV cannot adjust, sound goes to a display).
        Row(name: "software volume active", speakers: false, hasTV: true, software: true, tvCanAdjust: false, expected: .softwareVolume),
        // TV cannot adjust and the sound is not going to a display.
        Row(name: "TV cannot adjust, no display output", speakers: false, hasTV: true, software: false, tvCanAdjust: false, expected: .passThrough),
        // TV answer not known yet: old behavior, send to the TV.
        Row(name: "unknown TV answer", speakers: false, hasTV: true, software: false, tvCanAdjust: nil, expected: .tv),
        Row(name: "TV can adjust", speakers: false, hasTV: true, software: false, tvCanAdjust: true, expected: .tv),
        // Software volume is only ever set while the TV cannot adjust, but
        // the route trusts the flag it is given.
        Row(name: "software flag with TV can adjust", speakers: false, hasTV: true, software: true, tvCanAdjust: true, expected: .softwareVolume),
        Row(name: "software flag with unknown TV answer", speakers: false, hasTV: true, software: true, tvCanAdjust: nil, expected: .softwareVolume),
    ]

    private let allKeys: [MediaKeyEvent] = [.volumeUp, .volumeDown, .mute]

    func testRouteTable() {
        for row in rows {
            for key in allKeys {
                let route = VolumeKeyRoute.route(for: key,
                                                 speakersCanHandleVolumeKeys: row.speakers,
                                                 hasEnabledTV: row.hasTV,
                                                 softwareVolumeActive: row.software,
                                                 tvCanAdjustVolume: row.tvCanAdjust)
                XCTAssertEqual(route, row.expected, "\(row.name), key \(key)")
            }
        }
    }

    /// The mute key is routed like the volume keys, so it can never reach the
    /// TV while the speakers or software volume own the volume.
    func testMuteKeyFollowsTheSameRouteAsVolumeKeys() {
        for row in rows {
            let routes = allKeys.map {
                VolumeKeyRoute.route(for: $0,
                                     speakersCanHandleVolumeKeys: row.speakers,
                                     hasEnabledTV: row.hasTV,
                                     softwareVolumeActive: row.software,
                                     tvCanAdjustVolume: row.tvCanAdjust)
            }
            XCTAssertEqual(Set(routes).count, 1, row.name)
        }
    }
}
