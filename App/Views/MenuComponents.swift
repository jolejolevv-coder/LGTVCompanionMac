//
//  MenuComponents.swift
//  LGTV Companion
//
//  Building blocks of the menu bar panel, modelled on the macOS Control
//  Center: grouped cards, pill-shaped sliders, round icon buttons.
//

import SwiftUI

enum MenuMetrics {
    static let panelWidth: CGFloat = 320
    static let panelPadding: CGFloat = 12
    static let cardSpacing: CGFloat = 10
    static let cardPadding: CGFloat = 12
    static let cardCornerRadius: CGFloat = 14
    static let rowSpacing: CGFloat = 10
    static let sliderHeight: CGFloat = 24
    static let tileIconDiameter: CGFloat = 36
}

/// A grouped block of controls, like one module in Control Center.
struct MenuCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MenuMetrics.rowSpacing) {
            content
        }
        .padding(MenuMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MenuMetrics.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MenuMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

/// Card header: artwork, title, and a status line with an optional dot.
struct MenuCardHeader<Artwork: View>: View {
    let title: String
    let status: String
    var statusColor: Color?
    @ViewBuilder var artwork: Artwork

    var body: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let statusColor = statusColor {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Rounded-square symbol tile used as card artwork (like Settings rows).
struct SymbolTile: View {
    let systemName: String
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.gradient)
            )
    }
}

/// Small uppercase-free section caption inside a card.
struct MenuCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

/// Pill-shaped slider in the style of Control Center. Dragging updates the
/// value live; `onCommit` fires once when the drag ends, which is where
/// network commands belong.
struct PillSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var isEnabled = true
    let accessibilityLabel: String
    var onCommit: () -> Void = {}

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            // The fill never gets narrower than a circle, so it stays
            // grabbable and visible at zero.
            let fillWidth = max(height, geometry.size.width * fraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.white)
                    .frame(width: fillWidth)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 0.5)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        setValue(from: drag.location.x, width: geometry.size.width, knob: height)
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: MenuMetrics.sliderHeight)
        .opacity(isEnabled ? 1 : 0.35)
        .allowsHitTesting(isEnabled)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(Int(value))")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? step : -step
            value = min(max(value + delta, range.lowerBound), range.upperBound)
            onCommit()
        }
    }

    private func setValue(from x: CGFloat, width: CGFloat, knob: CGFloat) {
        // Map the usable travel (width minus one knob) to the range, so the
        // knob's center follows the pointer at both ends.
        let travel = max(width - knob, 1)
        let position = min(max((x - knob / 2) / travel, 0), 1)
        let raw = range.lowerBound + Double(position) * (range.upperBound - range.lowerBound)
        value = step > 0 ? (raw / step).rounded() * step : raw
    }
}

/// One volume line: mute button, pill slider, numeric value.
struct VolumeRow: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let isMuted: Bool
    var isEnabled = true
    let accessibilityLabel: String
    let onToggleMute: () -> Void
    var onCommit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isMuted ? Color.secondary : Color.primary)
            .disabled(!isEnabled)
            .help(isMuted ? "Unmute" : "Mute")

            PillSlider(value: $value, range: range, isEnabled: isEnabled,
                       accessibilityLabel: accessibilityLabel, onCommit: onCommit)

            Text("\(Int(value))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
        }
    }
}

/// Press feedback shared by the round and capsule buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Round icon button with a caption underneath.
struct ControlTile: View {
    let title: String
    let systemName: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: MenuMetrics.tileIconDiameter, height: MenuMetrics.tileIconDiameter)
                    .background(Color.primary.opacity(0.1), in: Circle())
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .help(title)
    }
}

/// Small capsule button, used for the input shortcuts.
struct CapsuleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Row of capsules where exactly one is selected, filling the card's width.
/// Used instead of the system segmented control, which does not stretch and
/// looks foreign next to the other capsules.
struct CapsulePicker<Option: Hashable>: View {
    let options: [Option]
    let selection: Option?
    let label: (Option) -> String
    var isEnabled = true
    let onSelect: (Option) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    onSelect(option)
                } label: {
                    Text(label(option))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.black : Color.primary)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Color.white : Color.primary.opacity(0.1), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
    }
}

// MARK: - Speaker artwork

/// Drawn pair of bookshelf speakers (dark cabinet, tweeter over an aluminium
/// woofer), in the look of the Edifier M90. Vector, so it stays sharp at any
/// size and needs no bundled photo.
struct SpeakerArtwork: View {
    var body: some View {
        HStack(spacing: 4) {
            SpeakerCabinet()
            SpeakerCabinet()
        }
        .frame(width: 44, height: 40)
        .accessibilityHidden(true)
    }
}

private struct SpeakerCabinet: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.11)],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)

                VStack(spacing: height * 0.07) {
                    tweeter(diameter: width * 0.32)
                    woofer(diameter: width * 0.70)
                }
            }
        }
    }

    private func tweeter(diameter: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.42), Color(white: 0.10)],
                                 center: .center, startRadius: 0, endRadius: diameter * 0.55))
            .overlay(Circle().strokeBorder(Color(white: 0.62), lineWidth: 0.6))
            .frame(width: diameter, height: diameter)
    }

    private func woofer(diameter: CGFloat) -> some View {
        ZStack {
            // Rubber surround.
            Circle().fill(Color(white: 0.05))
            // Aluminium cone.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.92), Color(white: 0.62), Color(white: 0.40)],
                                     center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: diameter * 0.5))
                .padding(diameter * 0.12)
            // Dust cap.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.98), Color(white: 0.70)],
                                     center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: diameter * 0.2))
                .frame(width: diameter * 0.30, height: diameter * 0.30)
        }
        .frame(width: diameter, height: diameter)
    }
}
