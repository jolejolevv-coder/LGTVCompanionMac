# CLAUDE.md

Project rules for LGTV Companion for macOS. They override the global
`~/.claude/CLAUDE.md` where both speak to the same thing.

## What this is

A macOS menu bar app (Swift package, SwiftUI, macOS 14.2+, no dependencies)
that controls an LG webOS TV over WebSocket and Edifier speakers over
Bluetooth LE. It reacts to sleep, wake, idle and the keyboard volume keys.
Details: `ARCHITECTURE.md`. Build and signing: `BUILD.md`.

## Layout

- `App/` SwiftUI app: scenes, menu bar panel, views, volume HUD.
- `Shared/` logic without UI (library `LGTVCompanionShared`), `DeviceManager`
  is the hub.
- `Tests/LGTVCompanionSharedTests/` unit tests, no hardware.
- `scripts/` `build-release.sh`, `create-signing-cert.sh`.
- `specs/features/` one spec per feature, `specs/roadmap.md` phases and status.
- `docs/uebergabe.md` handoff for the next session. Read it, the roadmap and
  this file at session start, nothing else.

## Commands

- `swift test` must stay green before every commit.
- `./scripts/build-release.sh [--install|--adhoc]` builds, signs, verifies the
  bundle and writes the DMG. `--install` replaces `/Applications` and
  relaunches.
- The package builds in Swift 6 language mode (tools 6.0, needs Swift 6.1 for
  `isolated deinit`). A clean build must have no warnings:
  `swift build --scratch-path /tmp/lgtv-sc`

## Hard rules

- The TV connection is `NWConnection(to: .url(wss://host:3001))` with TLS 1.2
  only. Do not change the URL form or the TLS version: separate host and port
  send no usable WebSocket upgrade, TLS 1.3 hangs the TV handshake.
- Tests never talk to a real TV, `UserDefaults.standard` or the real keychain.
  Use fakes (`TVTransport`) and injected stores.
- Never run `tccutil reset`. Never touch the keychain from scripts or tests.
- Keep the signing identity `LGTV Companion Local Signing`. A different
  signature silently drops the Accessibility and System Audio grants.
- Install with `--install` only after a phase is merged to main, and say so
  in the report. Never quit the app for anything else.

## Only the human can verify

Sound (software volume, speaker volume, HUD), the volume keys, Bluetooth with
the real speakers, TV power, sleep and wake overnight, permission prompts
after an install. Say so in the handoff instead of claiming it works.

## Plan first

No code before an approved spec. Every feature gets
`specs/features/<name>.md` with `## Goal`, `## Scope`, `## Acceptance criteria`,
`## Implementation plan`, `## Open questions`. The user approves the plan, then
you implement phase by phase, one commit per item, tests in the same phase.
Architecture, library and naming decisions are the user's call.

## Style

English code and identifiers, junior readable, one job per function, named
constants instead of magic numbers, every external call has a failure path,
log with `Log.tv` / `Log.speakers` / `Log.audio` / `Log.app`, no `print`.
