import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0B0D12)
    static let side = Color(hex: 0x08090D)
    static let card = Color(hex: 0x14171F)
    static let field = Color(hex: 0x1E222D)
    static let accent = Color(hex: 0x968CFF)
    static let muted = Color(hex: 0x9199A7)
    static let ok = Color(hex: 0x6EDCA0)
    static let error = Color(hex: 0xFF7878)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.card)
            )
    }
}

struct PillButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14.5, weight: .semibold))
            .foregroundStyle(primary ? Color(hex: 0x0C0C14) : Color.white)
            .padding(.horizontal, 17)
            .frame(height: 42)
            .background(
                Capsule().fill(primary ? Theme.accent : Theme.field)
            )
            .opacity(configuration.isPressed ? 0.65 : 1.0)
    }
}
