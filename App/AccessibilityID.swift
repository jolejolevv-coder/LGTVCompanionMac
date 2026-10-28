//
//  AccessibilityID.swift
//  LGTV Companion
//
//  Accessibility identifiers of the important controls, so UI automation
//  and agents can find a control and read its state through the
//  Accessibility tree. The scheme is `<window>.<area>.<control>`:
//  `menu` is the menu bar panel, `settings` the Settings window.
//  With several TVs or displays the same identifier appears once per card,
//  in panel order.
//

enum AccessibilityID {
    enum Menu {
        // TV card
        static let tvScreenOn = "menu.tv.screenOn"
        static let tvScreenOff = "menu.tv.screenOff"
        static let tvPowerOn = "menu.tv.powerOn"
        static let tvPowerOff = "menu.tv.powerOff"
        static let tvInput = "menu.tv.input"
        static func tvInput(hdmi number: Int) -> String { "\(tvInput).hdmi\(number)" }

        // Volume sliders: the TV's own, the Mac's software volume, the speakers.
        static let volumeTVSlider = "menu.volume.tvSlider"
        static let volumeMacSlider = "menu.volume.macSlider"
        static let volumeSpeakerSlider = "menu.volume.speakerSlider"

        // Speaker card
        static let speakerSubwoofer = "menu.speakers.subwoofer"
        static let speakerSound = "menu.speakers.sound"
        static let speakerInput = "menu.speakers.input"
        static let speakerNightMode = "menu.speakers.nightMode"

        // Displays card
        static let displayMode = "menu.display.mode"
    }

    enum Settings {
        static let launchAtLogin = "settings.general.launchAtLogin"
        static let volumeKeys = "settings.general.volumeKeys"
        static let softwareVolume = "settings.general.softwareVolume"

        static let userIdle = "settings.automation.userIdle"
        static let idleTimeout = "settings.automation.idleTimeout"

        static let speakerControl = "settings.speakers.control"
        static let speakerSound = "settings.speakers.sound"
        static let speakerWakeInputEnabled = "settings.speakers.wakeInputEnabled"
        static let speakerWakeInput = "settings.speakers.wakeInput"
        static let speakerPowerSave = "settings.speakers.powerSave"

        static let nightMode = "settings.nightMode.enabled"
        static let nightVolumeLimit = "settings.nightMode.volumeLimit"
        static let nightSubwoofer = "settings.nightMode.subwoofer"
        static let nightSchedule = "settings.nightMode.schedule"
    }
}
