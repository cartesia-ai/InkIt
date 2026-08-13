import SwiftUI

struct InkButtonStyle: ButtonStyle {
    enum Variant: Equatable { case ink, destructive, accent, accentSoft }

    var variant: Variant = .ink
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, variant: variant, compact: compact)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let variant: Variant
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        private var fill: Color {
            switch variant {
            case .ink:         return Color("InkFill")
            case .destructive: return .inkDanger
            case .accent:      return .accentColor
            case .accentSoft:  return .accentSoft
            }
        }

        private var textColor: Color {
            switch variant {
            case .ink:         return Color("InkFillText")
            case .destructive: return .white  // ds-allow: legible label on the red destructive fill
            case .accent:      return .white  // ds-allow: white label on the amber accent fill, matching the accent CTA
            case .accentSoft:  return .accentColor
            }
        }

        // accentSoft's fill is already light, so brightening it on hover barely
        // reads — gray it down instead, like a dimmed/disabled tint.
        private var graysOnHover: Bool { variant == .accentSoft }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
            configuration.label
                .font(compact ? .inkCalloutEmphasized : .inkBodyEmphasized)
                .foregroundStyle(textColor)
                .padding(.horizontal, compact ? 14 : 26)
                .padding(.vertical, compact ? 6 : 11)
                .background(
                    shape
                        .fill(fill)
                        .overlay(shape.fill(Color.gray.opacity(hovering && isEnabled && graysOnHover ? Hover.grayTintOpacity : 0)))
                        .brightness(hovering && isEnabled && !graysOnHover ? Hover.fillShift : 0)
                        .opacity(configuration.isPressed ? 0.82 : 1)
                        .animation(Hover.animation, value: hovering)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
