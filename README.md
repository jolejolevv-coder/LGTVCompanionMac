# LGTV Companion for macOS

Use your LG OLED/WebOS TV as a Mac monitor — without grabbing the remote.

The TV automatically follows your Mac: screen off when the Mac sleeps, instantly back on when it wakes. Inspired by [LGTVCompanion for Windows](https://github.com/JPersson77/LGTVCompanion).

## Features

- **Automatic power sync** – TV screen turns off when your Mac sleeps, shuts down, or the display sleeps; turns back on when the Mac wakes
- **Screen-off mode** – uses webOS "screen off" instead of a full power-off: picture returns instantly, no boot time, no HDMI re-handshake (toggleable per device)
- **Menu bar controls** – TV status, screen on/off, volume slider, mute, HDMI input switching, full power-off
- **Wake-on-LAN** – with retry logic for flaky post-wake networking, plus direct network wake when the TV is merely in standby
- **Auto-discovery** – finds WebOS TVs on your network via SSDP
- **Secure WebSocket** – connects via `wss://` (port 3001) with fallback to `ws://` (port 3000) for older firmware
- **Idle detection** – optionally turn the TV off after a period of inactivity
- **Launch at login** – runs quietly in the background

## Requirements

- macOS 14 (Sonoma) or newer
- LG WebOS TV on the same network (Ethernet recommended)
- TV setting enabled: **Settings → General → Devices → External Devices → "LG Connect Apps" / "Mobile TV On"** (enables Wake-on-LAN)

## Install

### From release

Download the DMG from [Releases](../../releases), drag the app to `/Applications`, done.

### Build from source

```bash
git clone <this-repo>
cd LGTVCompanionMac
./scripts/build-release.sh
cp -r "build/LGTV Companion.app" /Applications/
```

Or for development:

```bash
swift run LGTVCompanion
```

## Setup

1. Launch the app → **Scan** finds your TV (or add it manually with IP + MAC address)
2. Click **Pair Device** → accept the prompt on the TV (you have 60 seconds)
3. Done. Test with **Test Power Off / On**, then put your Mac to sleep — the TV should follow.

Tip: give the TV a static IP / DHCP reservation in your router.

## How it works

| Mac event | TV action |
|---|---|
| Sleep / display sleep / shutdown | Screen off (or full power-off) |
| Wake / display wake | Screen on, Wake-on-LAN if needed |
| User idle (optional) | Screen off after timeout |

System sleep is briefly delayed (max. 20 s) so the power-off command reliably reaches the TV before the network goes down.

## Troubleshooting

- **TV not found by scanner** – check that Mac and TV are on the same network/VLAN; grant the "Local Network" permission when macOS asks; enter IP + MAC manually as fallback
- **Pairing prompt never appears** – newer firmware requires `wss://` on port 3001; this app tries that first. Make sure "LG Connect Apps" is enabled
- **401 insufficient permissions** – remove the device in the app and pair again (permissions are granted at pairing time)
- **Wake-on-LAN unreliable over Wi-Fi** – use Ethernet, or enable "Turn on via Wi-Fi" on the TV

## Credits

Made by **Nahobino**. Inspired by [LGTVCompanion for Windows](https://github.com/JPersson77/LGTVCompanion) by Jörgen Persson.

## License

See [LICENSE](LICENSE).
