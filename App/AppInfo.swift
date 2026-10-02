//
//  AppInfo.swift
//  LGTV Companion
//
//  Facts about the app that used to be repeated as literals.
//

import Foundation

enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/jolejolevv-coder/LGTVCompanionMac")!
    static let issuesURL = repositoryURL.appendingPathComponent("issues")

    /// The version from the app bundle's Info.plist, which
    /// scripts/build-release.sh writes from its VERSION variable. That script
    /// is the single place to change the version. A bare `swift run` has no
    /// bundle and reports "dev".
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
