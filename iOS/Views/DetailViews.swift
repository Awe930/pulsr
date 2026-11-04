import SwiftUI
import Charts

// MARK: - Recovery

struct RecoveryDetailView: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        DetailScaffold(title: store.isToday ? "Today" : store.selected?.date.dayLabel ?? "", accent: Theme.recoveryColor(store.selected?.recovery)) {
            if let d = store.selected {
                HeroRing(progress: (d.recovery ?? 0) / 100, colors: Theme.recoveryGradient(d.recovery),
                         value: d.recovery.map(\.percent) ?? "–", unit: d.recovery == nil ? nil : "%", caption: "Recovery", orb: .recovery(d.recovery))
                GlassCard {
                    VStack(spacing: 0) {
                        if let hrv = d.raw.hrv, let base = Insights.hrvBaselineValue(d) {
                            ContributorRow(symbol: "waveform.path.ecg", title: "Heart Rate Variability", value: "\(Int(hrv))",
                                           arrowUp: hrv >= base, trend: hrv >= base ? .better : .worse)
                            Divider().opacity(0.4)
                        }
                        if let rhr = d.raw.restingHR, let b = d.rhrBaseline {
                            ContributorRow(symbol: "heart", title: "Resting Heart Rate", value: "\(Int(rhr.rounded()))",
                                           arrowUp: rhr >= b.mean, trend: rhr <= b.mean ? .better : .worse)
                            Divider().opacity(0.4)
                        }
                        if let resp = d.raw.respiratoryRate, let b = d.respBaseline {
                            ContributorRow(symbol: "lungs", title: "Respiratory Rate", value: resp.oneDecimal,
                                           arrowUp: resp >= b.mean, trend: abs(b.z(resp)) < 1 ? .neutral : .worse)
                            Divider().opacity(0.4)
                        }
                        ContributorRow(symbol: "moon.zzz", title: "Sleep Performance", value: d.sleepPerformance.map { "\($0.percent)%" } ?? "–")
                        Text("▲▼ Today vs. prior 30 days")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.black.opacity(0.25), in: .rect(cornerRadius: 10))
                            .padding(.top, 6)
                    }
                }
                InsightCallout(text: recoveryExplanation(d))
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Recovery · 14 days")
                        Chart(store.window(14)) { day in
                            if let r = day.recovery {
                                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Recovery", r))
                                    .foregroundStyle(Theme.recoveryColor(r).gradient)
                                    .cornerRadius(5)
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                        .frame(height: 160)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "HRV · 30 days")
                        TrendLine(points: store.window(30).compactMap { d in d.raw.hrv.map { TrendPoint(date: d.date, value: $0) } },
                                  baseline: Insights.hrvBaselineValue(d), color: Theme.green, unit: "ms")
                            .frame(height: 160)
                    }
                }
            }
        }
    }

    private func recoveryExplanation(_ d: DayScores) -> String {
        guard d.recovery != nil else { return "Recovery needs heart rate variability measured while you sleep. Wear your watch to bed tonight." }
        var parts: [String] = []
        if let change = Insights.hrvChange(d) {
            parts.append(abs(change) < 0.05 ? "Your HRV is typical" : change > 0 ? "Your HRV is elevated" : "Your HRV is suppressed")
        }
        if let rhr = d.raw.restingHR, let b = d.rhrBaseline {
            parts.append(abs(b.z(rhr)) < 1 ? "your RHR is typical" : rhr < b.mean ? "your RHR is lower than usual" : "your RHR is elevated")
        }
        if let p = d.sleepPerformance { parts.append(p >= 85 ? "sleep was optimal" : p >= 70 ? "sleep was sufficient" : "sleep fell short") }
        return parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst() + "."
    }
}

// MARK: - Sleep

struct SleepDetailView: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        DetailScaffold(title: store.isToday ? "Today" : store.selected?.date.dayLabel ?? "", accent: Theme.sleep[1]) {
            if let d = store.selected {
                HeroRing(progress: (d.sleepPerformance ?? 0) / 100, colors: Theme.sleep,
                         value: d.sleepPerformance.map(\.percent) ?? "–", unit: d.sleepPerformance == nil ? nil : "%", caption: "Sleep Performance", orb: .sleep, speed: 0.6)
                GlassCard {
                    VStack(spacing: 0) {
                        row("clock", "Hours vs. Needed", d.hoursVsNeeded)
                        Divider().opacity(0.4)
                        row("calendar", "Sleep Consistency", d.sleepConsistency)
                        Divider().opacity(0.4)
                        row("bed.double", "Sleep Efficiency", d.sleepEfficiency)
                        Divider().opacity(0.4)
                        row("sparkles", "Restorative Sleep", d.raw.sleep?.restorativeShare.map { min(1, $0 / 0.45) }, display: d.raw.sleep?.restorativeShare)
                        HStack(spacing: 14) {
                            legend(Theme.hurts, "Poor"); legend(Color.primary.opacity(0.7), "Sufficient"); legend(Theme.helps, "Optimal")
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.black.opacity(0.25), in: .rect(cornerRadius: 10))
                        .padding(.top, 6)
                    }
                }
                InsightCallout(text: Insights.sleepSummary(d))
                if let sleep = d.raw.sleep {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Eyebrow(text: "Sleep Stages")
                                Spacer()
                                Text("\(sleep.start.shortTime) – \(sleep.end.shortTime)").font(.caption).foregroundStyle(.secondary)
                            }
                            Hypnogram(sleep: sleep).frame(height: 170)
                            HStack {
                                ForEach([SleepStage.awake, .rem, .core, .deep], id: \.self) { stage in
                                    VStack(spacing: 2) {
                                        Text((stage == .core ? sleep.duration(of: .core) + sleep.duration(of: .asleep) : sleep.duration(of: stage)).hoursMinutes)
                                            .font(.system(.callout, design: .rounded).weight(.semibold))
                                        Text(stage.title).font(.caption2.weight(.semibold)).foregroundStyle(stageColor(stage))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Hours slept vs. needed · 14 days")
                        Chart(store.window(14)) { day in
                            if let asleep = day.raw.sleep?.asleep {
                                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", asleep / 3600))
                                    .foregroundStyle(LinearGradient(colors: Theme.sleep, startPoint: .bottom, endPoint: .top))
                                    .cornerRadius(5)
                            }
                            LineMark(x: .value("Day", day.date, unit: .day), y: .value("Need", day.sleepNeed / 3600))
                                .foregroundStyle(Color.primary.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                        .frame(height: 160)
                    }
                }
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ value: Double?, display: Double? = nil) -> some View {
        let shown = display ?? value
        return ContributorRow(symbol: symbol, title: title, value: shown.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", bar: value)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) { Capsule().fill(color).frame(width: 14, height: 4); Text(text).foregroundStyle(.secondary) }
    }
}

func stageColor(_ stage: SleepStage) -> Color {
    switch stage {
    case .awake: Theme.awake
    case .rem: Theme.rem
    case .core, .asleep: Theme.lightSleep
    case .deep: Theme.deep
    }
}

struct Hypnogram: View {
    var sleep: SleepSession
    var body: some View {
        Chart(sleep.segments) { seg in
            RectangleMark(xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                          y: .value("Stage", seg.stage == .asleep ? SleepStage.core.title : seg.stage.title), height: .ratio(0.7))
                .foregroundStyle(stageColor(seg.stage).gradient)
                .cornerRadius(3)
        }
        .chartYScale(domain: [SleepStage.awake.title, SleepStage.rem.title, SleepStage.core.title, SleepStage.deep.title])
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisGridLine().foregroundStyle(Color.primary.opacity(0.08)); AxisValueLabel(format: .dateTime.hour()) } }
    }
}

// MARK: - Strain

struct StrainDetailView: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        DetailScaffold(title: store.isToday ? "Today" : store.selected?.date.dayLabel ?? "", accent: Theme.strain[1]) {
            if let d = store.selected {
                let target = ScoreEngine.strainTarget(for: d)
                HeroRing(progress: d.strain / 21, colors: Theme.strain, value: d.strain.oneDecimal, unit: nil, caption: "Day Strain",
                         marker: target.lowerBound / 21, orb: .strain, speed: 1.3)
                Text("Target \(Int(target.lowerBound))–\(Int(target.upperBound)) based on your recovery")
                    .font(.caption).foregroundStyle(.secondary)
                GlassCard {
                    VStack(spacing: 0) {
                        ContributorRow(symbol: "heart", title: "Heart Rate Zones 1–3", value: (d.zoneMinutes[1...3].reduce(0, +) * 60).hoursMinutes)
                        Divider().opacity(0.4)
                        ContributorRow(symbol: "heart.fill", title: "Heart Rate Zones 4–5", value: (d.zoneMinutes[4...5].reduce(0, +) * 60).hoursMinutes)
                        Divider().opacity(0.4)
                        ContributorRow(symbol: "dumbbell", title: "Strength Activity Time", value: (d.strengthMinutes * 60).hoursMinutes)
                        Divider().opacity(0.4)
                        ContributorRow(symbol: "shoeprints.fill", title: "Steps", value: d.raw.steps.formatted(.number.precision(.fractionLength(0))))
                        Divider().opacity(0.4)
                        ContributorRow(symbol: "flame", title: "Active Calories", value: d.raw.activeEnergy.formatted(.number.precision(.fractionLength(0))))
                    }
                }
                InsightCallout(text: Insights.strainSummary(d))
                if !d.raw.heartRate.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow(text: "Heart Rate")
                            HeartRateChart(points: d.raw.heartRate, workouts: d.raw.workouts, maxHR: store.profile.maxHeartRate)
                                .frame(height: 180)
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "Time in zones")
                            ForEach((1...5).reversed(), id: \.self) { z in
                                ZoneBar(zone: z, minutes: d.zoneMinutes[z], total: max(d.zoneMinutes[1...5].reduce(0, +), 1))
                            }
                        }
                    }
                }
                if !d.raw.workouts.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "Activities")
                            ForEach(d.raw.workouts) { w in
                                ActivityRow(symbol: w.symbol, tint: Theme.strain[0], badge: (d.workoutStrain[w.id] ?? 0).oneDecimal,
                                            title: w.name, detail: "\(w.start.shortTime) · \(Int(w.duration / 60)) min")
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Zones are one sequential ramp of the strain colour, from light effort to all-out.
let zoneColors: [Color] = (0...5).map { Theme.strain[0].opacity(0.25 + Double($0) * 0.15) }

struct ZoneBar: View {
    var zone: Int
    var minutes: Double
    var total: Double
    var body: some View {
        HStack(spacing: 10) {
            Text("Z\(zone)").font(.caption.weight(.bold)).frame(width: 24, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(zoneColors[zone]).frame(width: max(4, geo.size.width * minutes / total))
                }
            }
            .frame(height: 10)
            Text((minutes * 60).hoursMinutes).font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
        }
    }
}

struct HeartRateChart: View {
    var points: [HeartRatePoint]
    var workouts: [WorkoutSummary]
    var maxHR: Double

    var body: some View {
        Chart {
            ForEach(workouts) { w in
                RectangleMark(xStart: .value("Start", w.start), xEnd: .value("End", w.end))
                    .foregroundStyle(Theme.strain[0].opacity(0.12))
            }
            ForEach(points, id: \.date) { p in
                LineMark(x: .value("Time", p.date), y: .value("BPM", p.bpm))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                    .foregroundStyle(Theme.strain[0])
            }
        }
        .chartYScale(domain: 40...maxHR)
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 4)) { _ in AxisGridLine().foregroundStyle(Color.primary.opacity(0.08)); AxisValueLabel(format: .dateTime.hour()) } }
    }
}

/// Simple line with an optional dashed baseline.
struct TrendPoint: Identifiable {
    var id: Date { date }
    var date: Date
    var value: Double
}

struct TrendLine: View {
    var points: [TrendPoint]
    var baseline: Double?
    var color: Color
    var unit: String

    /// Zoomed to your values (and baseline) so day-to-day movement shows.
    private var domain: ClosedRange<Double> {
        let values = points.map(\.value) + (baseline.map { [$0] } ?? [])
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.2, 2)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Day", p.date, unit: .day), yStart: .value(unit, domain.lowerBound), yEnd: .value(unit, p.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Day", p.date, unit: .day), y: .value(unit, p.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.2))
            }
            if let baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
    }
}

/// Strain (0–21) and Recovery (0–100 %) as two stacked charts, each on its own axis.
struct StrainRecoveryChart: View {
    var days: [DayScores]
    var compact = false

    private var xAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: days.count > 10 ? 5 : 1)) { _ in
            AxisValueLabel(format: days.count > 10 ? .dateTime.month(.abbreviated).day() : .dateTime.weekday(.narrow))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Strain · 0–21").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
            Chart(days) { d in
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Strain", d.strain), width: .ratio(0.55))
                    .foregroundStyle(Theme.strain[0].opacity(d.id == days.last?.id ? 1 : 0.5))
                    .cornerRadius(4)
            }
            .chartYScale(domain: 0...21)
            .chartYAxis { AxisMarks(values: [0, 7, 14, 21]) { _ in AxisGridLine().foregroundStyle(Theme.track); AxisValueLabel() } }
            .chartXAxis { xAxis }
            .frame(maxHeight: .infinity)
            Text("Recovery · 0–100%").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
            Chart(days.filter { $0.recovery != nil }) { d in
                let r = d.recovery ?? 0
                LineMark(x: .value("Day", d.date, unit: .day), y: .value("Recovery", r))
                    .foregroundStyle(.secondary.opacity(0.5))
                PointMark(x: .value("Day", d.date, unit: .day), y: .value("Recovery", r))
                    .foregroundStyle(Theme.recoveryColor(r))
                    .symbolSize(compact ? 40 : 60)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) { _ in AxisGridLine().foregroundStyle(Theme.track); AxisValueLabel() } }
            .chartXAxis { xAxis }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Focus and energy (Nine30)

struct FocusView: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        DetailScaffold(title: "Focus and energy", accent: Theme.yellow) {
            if let d = store.selected, let s = Focus.schedule(for: d, history: store.window(7), profile: store.profile) {
                let session = Focus.marketSession(on: d.date)
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Predicted alertness · from your wake time")
                        Chart {
                            if let session {
                                RectangleMark(xStart: .value("Open", session.start), xEnd: .value("Close", session.end),
                                              yStart: .value("Low", 0.0), yEnd: .value("High", 1.0))
                                    .foregroundStyle(Color.primary.opacity(0.06))
                            }
                            RectangleMark(xStart: .value("Peak start", s.peak.start), xEnd: .value("Peak end", s.peak.end),
                                          yStart: .value("Low", 0.0), yEnd: .value("High", 1.0))
                                .foregroundStyle(Theme.green.opacity(0.14))
                            RectangleMark(xStart: .value("Dip start", s.dip.start), xEnd: .value("Dip end", s.dip.end),
                                          yStart: .value("Low", 0.0), yEnd: .value("High", 1.0))
                                .foregroundStyle(Theme.hurts.opacity(0.16))
                            ForEach(s.curve()) { p in
                                LineMark(x: .value("Time", p.date), y: .value("Alertness", p.level))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(Color.primary)
                            }
                            if store.isToday {
                                RuleMark(x: .value("Now", Date.now)).foregroundStyle(Theme.yellow)
                            }
                        }
                        .chartYScale(domain: 0...1)
                        .chartYAxis(.hidden)
                        .frame(height: 190)
                        Text(Focus.sessionNote(s, session: session)).font(.callout).foregroundStyle(.secondary)
                    }
                }

                GlassCard {
                    VStack(spacing: 0) {
                        scheduleRow("Groggy until", s.grogginessEnds.shortTime, Color.primary.opacity(0.4))
                        Divider().opacity(0.4)
                        scheduleRow("Peak focus", "\(s.peak.start.shortTime)–\(s.peak.end.shortTime)", Color.primary)
                        Divider().opacity(0.4)
                        scheduleRow("Afternoon dip", "\(s.dip.start.shortTime)–\(s.dip.end.shortTime)", Theme.hurts)
                        Divider().opacity(0.4)
                        scheduleRow("Second wind", "\(s.secondWind.start.shortTime)–\(s.secondWind.end.shortTime)", Color.primary.opacity(0.7))
                        Divider().opacity(0.4)
                        scheduleRow("Wind down", s.windDown.shortTime, Theme.sleep[0])
                        Divider().opacity(0.4)
                        scheduleRow("Bedtime", s.bedtime.shortTime, Theme.sleep[0])
                    }
                }

                let end = store.isToday ? Date.now : min(s.bedtime, Calendar.current.startOfDay(for: d.date).addingTimeInterval(24 * 3600))
                let energy = Focus.energy(d, schedule: s, until: end)
                if energy.count > 1 {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Eyebrow(text: "Energy through the day")
                                Spacer()
                                Text("\(Int((energy.last?.level ?? 0).rounded())) now").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            Chart(energy) { p in
                                AreaMark(x: .value("Time", p.date), y: .value("Energy", p.level))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(LinearGradient(colors: [Theme.yellow.opacity(0.35), Theme.yellow.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                LineMark(x: .value("Time", p.date), y: .value("Energy", p.level))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(Theme.yellow)
                            }
                            .chartYScale(domain: 0...100)
                            .frame(height: 150)
                            Text("Starts from your Recovery when you wake, drains with stress and exercise, and recharges a little when you're calm.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let m = Focus.marketStress(d, session: session) {
                    InsightCallout(text: "Market hours: stress averaged \(m.average.oneDecimal) of 3, peaking at \(m.peak.level.oneDecimal) around \(m.peak.date.shortTime)." + (m.outsideAverage.map { " The rest of your waking day averaged \($0.oneDecimal)." } ?? ""))
                }

                InsightCallout(text: "Focus windows are a prediction from your wake time and sleep debt, not a measurement. Your morning check-in ratings will show whether they fit you.")
            } else {
                InsightCallout(text: "Focus windows appear once Nine30 has a few nights of sleep to learn your wake time.")
            }
        }
    }

    private func scheduleRow(_ title: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .padding(.vertical, 11)
    }
}
