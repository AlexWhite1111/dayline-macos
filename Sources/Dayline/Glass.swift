import AppKit
import SwiftUI

let daylineWarm = Color(red: 0.93, green: 0.66, blue: 0.33)

struct PressScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private final class PassthroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> PassthroughVisualEffectView {
        let view = PassthroughVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: PassthroughVisualEffectView, context: Context) {
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
    }
}

private struct GlassModifier<ShapeType: InsettableShape>: ViewModifier {
    let shape: ShapeType
    let usesNativeGlass: Bool
    let nativeGlassStyle: NativeGlassStyle
    let accentuated: Bool
    let shadowRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesNativeGlass, #available(macOS 26.0, *) {
            content
                .glassEffect(nativeGlass.interactive(), in: shape)
                .overlay { nativeEdge }
                .shadow(color: .black.opacity(0.12), radius: shadowRadius, y: 4)
        } else {
            customGlass(content)
        }
    }

    @available(macOS 26.0, *)
    private var nativeGlass: Glass {
        nativeGlassStyle == .clear ? .clear : .regular
    }

    private var nativeEdge: some View {
        shape.strokeBorder(
            accentuated
                ? AnyShapeStyle(daylineWarm.opacity(0.36))
                : AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.28),
                            Color(nsColor: .separatorColor).opacity(0.48),
                            .black.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ),
            lineWidth: 0.55
        )
        .allowsHitTesting(false)
    }

    private func customGlass(_ content: Content) -> some View {
        content
            .background {
                VisualEffectBackground()
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.stroke(
                    accentuated
                        ? daylineWarm.opacity(0.32)
                        : Color(nsColor: .separatorColor).opacity(0.68),
                    lineWidth: 0.65
                )
            }
            .shadow(color: .black.opacity(0.15), radius: shadowRadius, y: 5)
    }
}

extension View {
    func glassCapsule(
        usesNativeGlass: Bool,
        nativeGlassStyle: NativeGlassStyle,
        accentuated: Bool,
        shadowRadius: CGFloat
    ) -> some View {
        modifier(
            GlassModifier(
                shape: Capsule(),
                usesNativeGlass: usesNativeGlass,
                nativeGlassStyle: nativeGlassStyle,
                accentuated: accentuated,
                shadowRadius: shadowRadius
            )
        )
    }

    func glassCircle(
        usesNativeGlass: Bool,
        nativeGlassStyle: NativeGlassStyle,
        shadowRadius: CGFloat
    ) -> some View {
        modifier(
            GlassModifier(
                shape: Circle(),
                usesNativeGlass: usesNativeGlass,
                nativeGlassStyle: nativeGlassStyle,
                accentuated: false,
                shadowRadius: shadowRadius
            )
        )
    }
}
