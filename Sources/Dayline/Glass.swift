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

private struct GlassModifier<ShapeType: InsettableShape>: ViewModifier {
    let shape: ShapeType
    let nativeGlassStyle: NativeGlassStyle
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .glassEffect(nativeGlass.interactive(isInteractive), in: shape)
            .materialActiveAppearance(isInteractive ? .automatic : .inactive)
    }

    private var nativeGlass: Glass { nativeGlassStyle == .clear ? .clear : .regular }
}

extension View {
    func glassCapsule(nativeGlassStyle: NativeGlassStyle) -> some View {
        modifier(
            GlassModifier(
                shape: Capsule(),
                nativeGlassStyle: nativeGlassStyle,
                isInteractive: false
            )
        )
    }

    func glassCircle(nativeGlassStyle: NativeGlassStyle) -> some View {
        modifier(
            GlassModifier(
                shape: Circle(),
                nativeGlassStyle: nativeGlassStyle,
                isInteractive: true
            )
        )
    }
}
