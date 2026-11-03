import SwiftUI

enum Theme {
    // Every colour has a light and a dark value; the watch always uses the dark one.
    static let sleep = [Color.adaptive(0x6B5CE6, 0xA9A0FF), Color.adaptive(0x8B6CF0, 0xB49BFF)]
    static let strain = [Color.adaptive(0x0A8FD1, 0x2FD4FF), Color.adaptive(0x2F5BE0, 0x4F7BFF)]
    static let stress = [Color.adaptive(0x1E9BD7, 0x5AC8FA), Color.adaptive(0x0DB877, 0x30E0A1), Color.adaptive(0xD98200, 0xFFB340)]
    // Zone colours: the one accent each screen gets. Dark values match the Nine30 design canvas.
    static let green = Color.adaptive(0x0DA56B, 0x3DDC97)
    static let yellow = Color.adaptive(0xB07E00, 0xF5C451)
    static let red = Color.adaptive(0xD8452F, 0xFF7A6B)
    static let helps = Color.adaptive(0x0DB877, 0x2EF2A0)
    static let hurts = Color.adaptive(0xD9731A, 0xFFA845)
    static let screen = Color.adaptive(0xF2F4F7, 0x020306)
    static let track = Color.adaptive(0x0B0F14, 0xFFFFFF).opacity(0.09)
    // Sleep stages run light to dark by depth.
    static let awake = Color.adaptive(0xC9A27A, 0xE2B98E)
    static let rem = Color.adaptive(0xA39FF5, 0xC3C0FF)
    static let lightSleep = Color.adaptive(0x6F69E8, 0x8A85FF)
    static let deep = Color.adaptive(0x3F37B8, 0x5B54F0)
    static let backgroundTop = Color(hex: 0x0B1220)
    static let backgroundBottom = Color(hex: 0x05070D)

    static func recoveryColor(_ value: Double?) -> Color {
        guard let value else { return .gray }
        switch RecoveryZone(value) {
        case .green: return green
        case .yellow: return yellow
        case .red: return red
        }
    }

    static func recoveryGradient(_ value: Double?) -> [Color] {
        let c = recoveryColor(value)
        return [c.opacity(0.75), c]
    }

    static func stressColor(_ level: Double) -> Color {
        level < 1 ? stress[0] : level < 2 ? stress[1] : stress[2]
    }
}

extension Color {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        #if os(iOS)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
        #else
        return Color(hex: dark)
        #endif
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// A glowing progress ring with a rounded gradient stroke.
struct ScoreRing<Center: View>: View {
    var progress: Double            // 0...1
    var colors: [Color]
    var lineWidth: CGFloat = 10
    var marker: Double? = nil       // optional target tick, 0...1
    @ViewBuilder var center: Center

    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(shown, 0.001))
                .stroke(AngularGradient(colors: colors + [colors.last ?? .white], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(shown, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (colors.last ?? .white).opacity(0.55), radius: lineWidth * 0.9)
            if let marker {
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5, height: lineWidth + 6)
                    .offset(y: -(lineWidth / 2 + 3))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .rotationEffect(.degrees(360 * marker))
            }
            center
        }
        .padding(lineWidth / 2)
        .onAppear { withAnimation(.spring(duration: 1.2, bounce: 0.15)) { shown = progress.clamped(0, 1) } }
        .onChange(of: progress) { _, new in withAnimation(.spring(duration: 0.8)) { shown = new.clamped(0, 1) } }
    }
}

extension TimeInterval {
    /// "7:42" style hours:minutes.
    var hoursMinutes: String {
        let total = Int((self / 60).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension Double {
    var oneDecimal: String { String(format: "%.1f", self) }
    var percent: String { "\(Int(rounded()))" }
}

extension Date {
    var dayLabel: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}
