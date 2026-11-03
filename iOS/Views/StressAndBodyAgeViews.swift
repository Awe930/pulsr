import SwiftUI
import Charts

// MARK: - Stress

struct StressView: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        DetailScaffold(title: "Stress Monitor", accent: Theme.stress[1]) {
            if let d = store.selected {
                let current = d.latestStress ?? 0
                StressGauge(value: current, updated: d.stress.last?.date)
                    .frame(height: 210)
                    .padding(.top, 10)
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Through the day")
                        Chart {
                            ForEach(d.raw.workouts) { w in
                                RectangleMark(xStart: .value("Start", w.start), xEnd: .value("End", w.end))
                                    .foregroundStyle(Theme.strain[0].opacity(0.14))
                            }
                            if let sleep = d.raw.sleep {
                                RectangleMark(xStart: .value("Start", max(sleep.start, d.date)), xEnd: .value("End", sleep.end))
                                    .foregroundStyle(Color.primary.opacity(0.05))
                            }
                            ForEach(d.stress) { p in
                                LineMark(x: .value("Time", p.date), y: .value("Stress", p.level))
                                    .interpolationMethod(.catmullRom)
                                    .lineStyle(StrokeStyle(lineWidth: 2.2))
                                    .foregroundStyle(LinearGradient(colors: Theme.stress, startPoint: .bottom, endPoint: .top))
                            }
                        }
                        .chartYScale(domain: 0...3)
                        .chartYAxis { AxisMarks(values: [0, 1, 2, 3]) { _ in AxisGridLine().foregroundStyle(Color.primary.opacity(0.08)); AxisValueLabel() } }
                        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 4)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
                        .frame(height: 190)
                    }
                }
                InsightCallout(text: Insights.stressSummary(d))
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Total day")
                        let total = Double(max(d.stress.count, 1))
                        let shares = [d.stress.filter { $0.level < 1 }.count, d.stress.filter { (1..<2).contains($0.level) }.count, d.stress.filter { $0.level >= 2 }.count]
                            .map { Double($0) / total }
                        GeometryReader { geo in
                            HStack(spacing: 3) {
                                ForEach(0..<3) { i in
                                    Capsule().fill(Theme.stress[i]).frame(width: max(2, geo.size.width * shares[i] - 3))
                                }
                            }
                        }
                        .frame(height: 10)
                        HStack {
                            ForEach(0..<3) { i in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(["Low", "Medium", "High"][i]).font(.caption2.weight(.bold)).foregroundStyle(Theme.stress[i])
                                    Text("\(Int(shares[i] * 100))%").font(.system(.callout, design: .rounded).weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct StressGauge: View {
    var value: Double
    var updated: Date?

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(AngularGradient(colors: Theme.stress, center: .center, startAngle: .degrees(0), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: Theme.stressColor(value).opacity(0.5), radius: 10)
            Capsule()
                .fill(Color.primary)
                .frame(width: 4, height: 22)
                .offset(y: -96)
                .rotationEffect(.degrees(-135 + 270 * value / 3))
            VStack(spacing: 2) {
                BigNumber(text: value.oneDecimal, size: 56)
                Text(StressLevel(value).rawValue)
                    .font(.headline)
                    .foregroundStyle(Theme.stressColor(value))
                if let updated {
                    Text("Last updated \(updated.shortTime)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 200, height: 200)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Body age

struct BodyAgeView: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        DetailScaffold(title: "Healthspan", accent: Theme.green) {
            if let age = store.bodyAge {
                ZStack {
                    HaloOrb(palette: .recovery(80), energy: 0.3, speed: 0.45)
                        .frame(width: 200, height: 200)
                        .padding(.vertical, 45)
                        .opacity(0.9)
                    VStack(spacing: 6) {
                        BigNumber(text: age.bodyAge.oneDecimal, size: 60)
                        Text("Body age").font(.headline).foregroundStyle(Color.primary.opacity(0.8))
                        Text(age.difference <= 0 ? "\(abs(age.difference).oneDecimal) years younger" : "\(age.difference.oneDecimal) years older")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(age.difference <= 0 ? Theme.green : Theme.hurts)
                    }
                }
                .padding(.vertical, 10)

                GlassCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Eyebrow(text: "What moves it")
                            Spacer()
                            Text("Years").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 6)
                        ForEach(age.factors) { f in
                            FactorRow(factor: f)
                        }
                    }
                }
                InsightCallout(text: bodyAgeText(age))
                Text("Body Age is an estimate built from published population norms for VO₂ max, resting heart rate, HRV, sleep and activity. It is a motivational trend, not a medical measurement.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
            } else {
                GlassCard { Text("Body Age needs at least a week of data.").foregroundStyle(.secondary) }
                    .padding(.top, 60)
            }
        }
    }

    private func bodyAgeText(_ age: BodyAgeResult) -> String {
        guard let worst = age.factors.last, worst.years > 0.3 else {
            return "Every factor is working in your favor. Keep your current habits to hold this Body Age."
        }
        let best = age.factors.first
        var text = "\(worst.name) is adding \(worst.years.oneDecimal) years — the biggest lever you have right now."
        if let best, best.years < 0 { text += " \(best.name) is your strongest asset (\(best.years.oneDecimal) years)." }
        return text
    }
}

struct FactorRow: View {
    var factor: BodyAgeFactor
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(factor.name).font(.subheadline.weight(.semibold))
                Text(factor.value).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            GeometryReader { geo in
                let half = geo.size.width / 2
                let w = min(half, half * abs(factor.years) / 4)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Rectangle().fill(Color.primary.opacity(0.3)).frame(width: 1).offset(x: half)
                    Capsule()
                        .fill(factor.years <= 0 ? Theme.helps : Theme.hurts)
                        .frame(width: max(w, 3))
                        .offset(x: factor.years <= 0 ? half - w : half)
                }
            }
            .frame(width: 110, height: 8)
            Text(String(format: "%+.1f", factor.years))
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(factor.years <= 0 ? Theme.helps : Theme.hurts)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}

/// A slowly rotating sphere of glowing particles.
struct ParticleSphere: View {
    var color: Color
    var count: Int

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let r = min(size.width, size.height) / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(Gradient(colors: [.clear, color.opacity(0.10), color.opacity(0.35)]),
                                               center: center, startRadius: r * 0.3, endRadius: r))
                ctx.addFilter(.blur(radius: 0.3))
                let golden = Double.pi * (3 - sqrt(5))
                for i in 0..<count {
                    // Fibonacci sphere, biased toward the shell
                    let y = 1 - 2 * (Double(i) + 0.5) / Double(count)
                    let ring = sqrt(1 - y * y)
                    let theta = golden * Double(i) + t * 0.25
                    let shell = 0.78 + 0.22 * abs(sin(Double(i) * 12.9898))
                    let x = cos(theta) * ring * shell, z = sin(theta) * ring * shell
                    let depth = (z + 1) / 2
                    let p = CGPoint(x: center.x + x * r, y: center.y + y * shell * r)
                    let s = 0.8 + depth * 2.4 * (0.5 + 0.5 * abs(sin(Double(i))))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                             with: .color(color.opacity(0.25 + 0.75 * depth)))
                }
            }
        }
        .drawingGroup()
    }
}
