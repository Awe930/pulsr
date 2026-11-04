import SwiftUI

// MARK: - Surfaces

extension View {
    /// Content cards get a quiet fill and a hairline edge; Liquid Glass stays on controls (buttons, tab bar), as Apple intends.
    func cardSurface(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill((tint ?? Color.primary).opacity(tint == nil ? 0.05 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    var tint: Color? = nil
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: cornerRadius, tint: tint)
    }
}

/// Screen background: near-black (or pale grey) with slowly drifting colour light and fine grain.
/// The accent tints the light so each screen picks up its orb's colour.
struct AuroraBackground: View {
    var accent: Color = Theme.green
    var secondary: Color = Color(hex: 0x4F7BFF)
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    Theme.screen
                    blob(accent, dark ? 0.20 : 0.16, x: 0.5 + 0.06 * sin(t * 0.05), y: 0.24, r: w * 0.9)
                    blob(secondary, dark ? 0.20 : 0.12, x: 0.0 + 0.05 * cos(t * 0.04), y: 0.0, r: w * 0.8)
                    blob(Color(hex: 0x7B6CFF), dark ? 0.22 : 0.10, x: 1.0, y: 0.06 + 0.04 * sin(t * 0.06), r: w * 0.8)
                    blob(accent, dark ? 0.10 : 0.10, x: 0.5, y: 1.1, r: w)
                }
                .frame(width: w, height: h)
                .drawingGroup()
                Rectangle().fill(.white)
                    .colorEffect(ShaderLibrary.filmGrain(.float(dark ? 0.10 : 0.05)))
                    .blendMode(dark ? .overlay : .multiply)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, _ opacity: Double, x: Double, y: Double, r: CGFloat) -> some View {
        GeometryReader { geo in
            RadialGradient(colors: [color.opacity(opacity), .clear], center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: r)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Typography helpers

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// Three small bars plus a line saying what the score rests on.
struct ConfidenceChip: View {
    var level: ScoreConfidence
    var detail: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(1...3, id: \.self) { i in
                    Capsule()
                        .fill(i <= level.rawValue ? tint : Color.secondary.opacity(0.3))
                        .frame(width: 10, height: 5)
                }
            }
            .accessibilityHidden(true)
            Text(detail.isEmpty ? level.title : "\(level.title) · \(detail)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .cardSurface(cornerRadius: 100)
        .accessibilityElement(children: .combine)
    }
}

struct BigNumber: View {
    var text: String
    var unit: String? = nil
    var size: CGFloat = 34

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(text)
                .font(.system(size: size, weight: size > 40 ? .thin : .regular))
                .tracking(size > 40 ? -size * 0.04 : 0)
                .contentTransition(.numericText())
            if let unit {
                Text(unit).font(.system(size: size * 0.4, weight: .light))
            }
        }
        .monospacedDigit()
    }
}

struct SectionTitle: View {
    var title: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack {
            Text(title).font(.title2.weight(.semibold))
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
    }
}

// MARK: - Rows

enum Trend {
    case better, worse, neutral
    var color: Color {
        switch self {
        case .better: Theme.helps
        case .worse: Theme.hurts
        case .neutral: .secondary
        }
    }
}

/// "HEART RATE VARIABILITY ……… 124 ▲" row used on every detail screen.
struct ContributorRow: View {
    var symbol: String
    var title: String
    var value: String
    var arrowUp: Bool? = nil
    var trend: Trend = .neutral
    var bar: Double? = nil   // 0…1, optional quality bar

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if let bar {
                QualityBar(value: bar).frame(width: 70)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
            if let arrowUp {
                Image(systemName: arrowUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.caption2)
                    .foregroundStyle(trend.color)
            } else {
                Circle().fill(.secondary).frame(width: 6, height: 6).padding(.horizontal, 2)
            }
        }
        .padding(.vertical, 12)
    }
}

/// Three-segment poor / sufficient / optimal indicator.
struct QualityBar: View {
    var value: Double
    var body: some View {
        let level = value < 0.6 ? 0 : value < 0.85 ? 1 : 2
        let colors: [Color] = [Theme.hurts, Color.primary.opacity(0.7), Theme.helps]
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i == level ? colors[level] : Color.primary.opacity(0.12))
                    .frame(height: 4)
            }
        }
    }
}

struct InsightCallout: View {
    var text: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(.callout).foregroundStyle(.primary)
            if let action {
                Button {
                    onAction?()
                } label: {
                    Label(action, systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0x8FA8FF), Color(hex: 0xB28CFF)], startPoint: .leading, endPoint: .trailing))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: 22)
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

/// The big orb header shared by Recovery, Sleep and Strain detail screens.
struct HeroRing: View {
    var progress: Double
    var colors: [Color]
    var value: String
    var unit: String?
    var caption: String
    var marker: Double? = nil
    var orb: OrbPalette = .spectral
    var speed: Double = 1

    var body: some View {
        VStack(spacing: 8) {
            HaloOrb(palette: orb, speed: speed)
                .frame(width: 168, height: 168)
                .padding(.top, 26)
                .padding(.bottom, 18)
            BigNumber(text: value, unit: unit, size: 66)
            Text(caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }
}

/// Wraps detail screens in the standard background + scroll.
struct DetailScaffold<Content: View>: View {
    var title: String
    var accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 16) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground(accent: accent) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
