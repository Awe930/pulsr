import SwiftUI
import Charts

struct TrendsView: View {
    @Environment(MetricsStore.self) private var store
    @State private var range = 7

    var body: some View {
        let days = Array(store.days.suffix(range))
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Trends").font(.largeTitle.weight(.bold))
                    Spacer()
                }
                .padding(.top, 8)

                Picker("Range", selection: $range) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)

                averages(days)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Eyebrow(text: "Strain & Recovery")
                            Spacer()
                            HStack(spacing: 10) {
                                Label("Strain", systemImage: "circle.fill").foregroundStyle(Theme.strain[0])
                                Label("Recovery", systemImage: "circle.fill").foregroundStyle(Theme.green)
                            }
                            .font(.caption2.weight(.semibold))
                            .labelStyle(DotLabelStyle())
                        }
                        StrainRecoveryChart(days: days, compact: range > 7).frame(height: 240)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Heart rate variability")
                        TrendLine(points: days.compactMap { d in d.raw.hrv.map { TrendPoint(date: d.date, value: $0) } },
                                  baseline: days.last.flatMap(Insights.hrvBaselineValue), color: Theme.green, unit: "ms")
                            .frame(height: 150)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Resting heart rate")
                        TrendLine(points: days.compactMap { d in d.raw.restingHR.map { TrendPoint(date: d.date, value: $0) } },
                                  baseline: days.last?.rhrBaseline?.mean, color: Theme.red, unit: "bpm")
                            .frame(height: 150)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Sleep")
                        Chart(days) { d in
                            if let asleep = d.raw.sleep?.asleep {
                                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Hours", asleep / 3600))
                                    .foregroundStyle(LinearGradient(colors: Theme.sleep, startPoint: .bottom, endPoint: .top))
                                    .cornerRadius(4)
                            }
                        }
                        .frame(height: 150)
                    }
                }
                if store.bodyAge != nil {
                    NavigationLink(value: Route.bodyAge) {
                        GlassCard(tint: Theme.green) {
                            HStack {
                                Label("Healthspan & Body Age", systemImage: "hourglass")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground(accent: Color(hex: 0x4F7BFF), secondary: Theme.green) }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func averages(_ days: [DayScores]) -> some View {
        func avg(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        let rec = avg(days.compactMap(\.recovery))
        let strain = avg(days.map(\.strain))
        let sleep = avg(days.compactMap { $0.raw.sleep?.asleep })
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                stat("Avg Recovery", rec.map { "\($0.percent)%" } ?? "–", Theme.recoveryColor(rec))
                stat("Avg Strain", strain?.oneDecimal ?? "–", Theme.strain[0])
                stat("Avg Sleep", sleep?.hoursMinutes ?? "–", Theme.sleep[0])
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(color)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.font(.system(size: 6)); configuration.title.foregroundStyle(.secondary) }
    }
}
