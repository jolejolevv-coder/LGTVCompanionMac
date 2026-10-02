//
//  VolumeHUD.swift
//  LGTV Companion
//
//  Small on-screen level display for the software volume. The app swallows
//  the volume keys in that mode, so macOS shows no overlay of its own.
//

import AppKit
import LGTVCompanionShared
import SwiftUI

final class VolumeHUDModel: ObservableObject {
    @Published var level: Double = 1
    @Published var muted = false
}

/// Main thread only.
final class VolumeHUD {
    static let shared = VolumeHUD()

    private static let size = NSSize(width: 280, height: 52)
    /// Distance from the top-right corner of the screen's usable area.
    private static let screenMargin: CGFloat = 12
    private static let visibleSeconds: TimeInterval = 1.5
    private static let fadeSeconds: TimeInterval = 0.25

    private let model = VolumeHUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(level: Double, muted: Bool) {
        model.level = level
        model.muted = muted

        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        // Restart the hide timer on every key press, so the display stays up
        // while the key is held or the knob is turned.
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleSeconds, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        // Purely informational: never take clicks or focus from the user.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: VolumeHUDView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: area.maxX - Self.size.width - Self.screenMargin,
            y: area.maxY - Self.size.height - Self.screenMargin
        ))
    }

    private func fadeOut() {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeSeconds
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // A key press during the fade made it visible again: keep it.
            guard let panel = self?.panel, panel.alphaValue == 0 else { return }
            panel.orderOut(nil)
        })
    }
}

private struct VolumeHUDView: View {
    @ObservedObject var model: VolumeHUDModel

    private var filledSteps: Int {
        model.muted ? 0 : Int((model.level * Double(SoftwareVolume.stepCount)).rounded())
    }

    private var iconName: String {
        if model.muted || filledSteps == 0 { return "speaker.slash.fill" }
        let fraction = Double(filledSteps) / Double(SoftwareVolume.stepCount)
        if fraction < 1.0 / 3.0 { return "speaker.wave.1.fill" }
        if fraction < 2.0 / 3.0 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 26, alignment: .leading)

            HStack(spacing: 3) {
                ForEach(0..<SoftwareVolume.stepCount, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(step < filledSteps ? 0.9 : 0.2))
                        .frame(height: 7)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
