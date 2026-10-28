//
//  Log.swift
//  LGTV Companion Shared
//
//  One place for the app's loggers. Read them with:
//    log stream --predicate 'subsystem == "com.lgtvcompanion.mac"'
//

import os

public enum Log {
    private static let subsystem = "com.lgtvcompanion.mac"

    /// TV connection, commands and discovery.
    public static let tv = Logger(subsystem: subsystem, category: "tv")
    /// Edifier speakers over Bluetooth.
    public static let speakers = Logger(subsystem: subsystem, category: "speakers")
    /// Software volume and Core Audio.
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    /// App lifecycle, settings, login item.
    public static let app = Logger(subsystem: subsystem, category: "app")
}
