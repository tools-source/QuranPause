import SwiftUI

enum QT {
    static let paper = adaptive(0xF7F6F0, 0x101A15)
    static let surface = adaptive(0xFFFFFF, 0x1B2A22)
    static let green = adaptive(0x204D40, 0xABD8BD)
    static let forest = Color(hex: 0x204D40)
    static let ink = adaptive(0x203C33, 0xEAF1E7)
    static let muted = adaptive(0x788279, 0xACBDAF)
    static let sage = adaptive(0xE6EBDD, 0x2B3C30)
    static let gold = adaptive(0xB58C4B, 0xD6B879)
    static let line = adaptive(0xE3E5DB, 0x34463A)
    private static func adaptive(_ light: UInt, _ dark: UInt) -> Color {
        Color(uiColor: UIColor { trait in
            let value = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        })
    }
    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
    /// The app's standard motion: quick to respond, settling without bounce.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.84)
}

/// Gentle press feedback for buttons and tappable cards.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    static var pressableRow: PressableStyle { PressableStyle(scale: 0.985) }
}

/// Fades content in, lifting it into place, the first time it appears.
/// With Reduce Motion it only fades.
private struct Reveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear { withAnimation(.easeOut(duration: 0.5).delay(delay)) { shown = true } }
    }
}
extension View {
    /// Reveals sections in reading order; `order` staggers them slightly.
    func reveal(_ order: Int = 0) -> some View { modifier(Reveal(delay: Double(min(order, 8)) * 0.06)) }
}
extension Color {
    init(hex: UInt) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        Image("BrandLogo").resizable().scaledToFit()
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}
struct PrimaryButton: View {
    var title: String
    var symbol = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Spacer(); Text(LocalizedStringKey(title)); Image(systemName: symbol).contentTransition(.symbolEffect(.replace)); Spacer() }
                .font(.system(size: 16, weight: .semibold)).padding(.vertical, 18)
                .foregroundStyle(.white).background(QT.forest.gradient, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: QT.forest.opacity(0.22), radius: 12, y: 6)
        }.buttonStyle(.pressable)
    }
}
struct Eyebrow: View {
    var text: String
    var body: some View { Text(LocalizedStringKey(text)).textCase(.uppercase).font(.system(size: 10, weight: .bold)).tracking(I18n.isArabic ? 0 : 2).foregroundStyle(QT.muted) }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).background(QT.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(QT.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.035), radius: 14, y: 6)
    }
}
struct PageHeading: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: eyebrow)
            Text(LocalizedStringKey(title)).font(QT.serif(36)).foregroundStyle(QT.ink)
            Text(LocalizedStringKey(subtitle)).font(.system(size: 15)).foregroundStyle(QT.muted).lineSpacing(4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
