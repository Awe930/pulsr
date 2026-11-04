import SwiftUI
import Charts

struct TodayView: View {
    @Environment(MetricsStore.self) private var store
    @State private var showSettings = false
    @State private var showCheckIn = false

    var body: some View {
        let day = store.selected
        ScrollView {
            VStack(spacing: 16) {
                header
                if let day {
                    rings(day)
                    bodyCheckAlert(day)
                    insight(day)
                    if store.isToday { checkInCard(day) }
                    monitors(day)
                    SectionTitle(title: "My Day")
                    activities(day)
                    if store.isToday { tonight(day) }
                    weekChart
                    bodyAgeTeaser
                } else if store.isLoading {
                    ProgressView().padding(.top, 120)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load() }
        .background { AuroraBackground(accent: Theme.recoveryColor(day?.recovery)) }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showCheckIn) { CheckInView() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { showSettings = true } label: {
                Text(store.profile.initials)
                    .font(.footnote.weight(.bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 6) {
                    Button { withAnimation { store.step(-1) } } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .disabled(store.selectedIndex == 0)
                    Text(store.isToday ? "Today" : (store.selected?.date.dayLabel ?? ""))
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 110)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .glassEffect(.regular, in: .capsule)
                    Button { withAnimation { store.step(1) } } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .disabled(store.isToday)
                }
            }
            Spacer()

            Image(systemName: store.source == .demo ? "sparkles.rectangle.stack" : "applewatch")
                .font(.title3)
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: .circle)
        }
        .padding(.top, 6)
    }

    // MARK: Rings

    private func rings(_ d: DayScores) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: Route.recovery) {
                VStack(spacing: 0) {
                    // Smaller orb inside a ring that carries the zone colour, so the zone reads at a glance.
                    ZStack {
                        Circle().stroke(Theme.track, lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: max(0.001, (d.recovery ?? 0) / 100))
                            .stroke(Theme.recoveryColor(d.recovery), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        HaloOrb(palette: .recovery(d.recovery))
                            .frame(width: 168, height: 168)
                    }
                    .frame(width: 220, height: 220)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                    BigNumber(text: d.recovery.map(\.percent) ?? "–", unit: d.recovery == nil ? nil : "%", size: 76)
                    if d.recovery == nil {
                        Text("Recovery · waiting for sleep").font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                    } else {
                        (Text("Recovery · ").foregroundStyle(.secondary)
                         + Text(Insights.headline(d).title).foregroundStyle(Theme.recoveryColor(d.recovery)).fontWeight(.semibold))
                            .font(.subheadline)
                            .padding(.top, 8)
                        ConfidenceChip(level: d.confidence, detail: d.confidenceDetail, tint: Theme.recoveryColor(d.recovery))
                            .padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    NavigationLink(value: Route.sleep) {
                        // Sleep balance against your goal: debt (purple), on target, or surplus (blue). Ring is full at 3 h either way.
                        let hours = d.sleepBalance / 3600
                        // Last night on its own, next to the 14-night balance: trend and single night together.
                        let lastNight = d.raw.sleep.map { $0.asleep - store.profile.sleepGoalHours * 3600 }
                        let lastText = lastNight.map { " · last \($0 < 0 ? "−" : "+")\(abs($0).hoursMinutes)" } ?? ""
                        MetricCapsule(progress: min(abs(hours) / 3, 1),
                                      color: hours < 0 ? Theme.sleep[0] : Theme.strain[0],
                                      value: d.sleepOnTarget ? "On target" : "\(hours < 0 ? "−" : "+")\(String(format: "%.1f", abs(hours))) h",
                                      title: (d.sleepOnTarget ? "Balance" : hours < 0 ? "Debt" : "Surplus") + lastText)
                    }
                    NavigationLink(value: Route.strain) {
                        let target = ScoreEngine.strainTarget(for: d)
                        MetricCapsule(progress: d.strain / 21, color: Theme.strain[0], value: "\(d.strain.oneDecimal)/21",
                                      title: "Strain · aim \(Int(target.lowerBound))–\(Int(target.upperBound))")
                    }
                }
            }
            .padding(.top, 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: Cards

    private func insight(_ d: DayScores) -> some View {
        let text = Insights.headline(d)
        // Neutral glass: the zone colour lives in the dot and the ring, not in a tinted card.
        return GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(Theme.recoveryColor(d.recovery)).frame(width: 8, height: 8)
                    Text(text.title).font(.title3.weight(.semibold))
                    Spacer()
                    if d.isCalibrating {
                        Text("Calibrating").font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .glassEffect(.regular.tint(Theme.yellow.opacity(0.3)), in: .capsule)
                    }
                }
                Text(text.body).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// Apple-Vitals-style rule: one odd vital is noise, two or more at once is worth a look.
    @ViewBuilder private func bodyCheckAlert(_ d: DayScores) -> some View {
        let out = HealthMonitor.metrics(for: d).filter { !$0.inRange }
        if out.count >= 2 {
            NavigationLink(value: Route.healthMonitor) {
                GlassCard(tint: Theme.hurts) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.hurts)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Body check: \(out.count) vitals out of range").font(.headline)
                            Text(out.map(\.name).joined(separator: ", ") + ". Two or more at once can be an early sign of illness, overreach or a poor night. Consider an easier day.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func checkInCard(_ d: DayScores) -> some View {
        let entry = store.dayLog(for: d.date)
        let status = entry.status ?? .normal
        let candidates: [String?] = [
            entry.readiness.map { "felt \($0) of 5" },
            entry.morningRMSSD.map { "HRV \(Int($0.rounded())) ms" },
            status == .normal ? nil : status.title,
        ]
        let parts = candidates.compactMap { $0 }
        let detail = entry.checkedInAt.map { "Done at \($0.shortTime)" + (parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")) }
            ?? "Not done yet · about 2 minutes"
        return GlassCard(padding: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Morning check-in").font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(entry.checkedInAt == nil ? "Start" : "Redo") { showCheckIn = true }
                    .buttonStyle(.glass)
            }
        }
    }

    private func monitors(_ d: DayScores) -> some View {
        let health = HealthMonitor.metrics(for: d)
        let inRange = health.filter(\.inRange).count
        let stress = d.latestStress
        return HStack(spacing: 12) {
            NavigationLink(value: Route.healthMonitor) {
                GlassCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Eyebrow(text: "Body check"); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                        HStack(spacing: 10) {
                            Image(systemName: inRange == health.count ? "checkmark" : "exclamationmark")
                                .font(.caption.weight(.bold))
                                .frame(width: 26, height: 26)
                                .background((inRange == health.count ? Theme.green : Theme.yellow).opacity(0.25), in: .rect(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(inRange == health.count ? "All typical" : "\(health.count - inRange) out of range")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(inRange == health.count ? Theme.green : Theme.yellow)
                                Text("\(inRange) of \(health.count) vitals").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            NavigationLink(value: Route.stress) {
                GlassCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Eyebrow(text: "Stress"); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                        HStack(spacing: 10) {
                            Text(stress?.oneDecimal ?? "–")
                                .font(.callout.weight(.bold).monospacedDigit())
                                .frame(width: 34, height: 26)
                                .background(Theme.stressColor(stress ?? 0).opacity(0.25), in: .rect(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stress.map { StressLevel($0).rawValue } ?? "No data")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.stressColor(stress ?? 0))
                                Text(d.stress.last?.date.shortTime ?? "—").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func activities(_ d: DayScores) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Activities")
                if let sleep = d.raw.sleep {
                    NavigationLink(value: Route.sleep) {
                        ActivityRow(symbol: "moon.fill", tint: Theme.sleep[0], badge: sleep.asleep.hoursMinutes, title: "Sleep",
                                    detail: "\(sleep.start.shortTime) – \(sleep.end.shortTime)")
                    }
                }
                ForEach(d.raw.workouts) { w in
                    NavigationLink(value: Route.strain) {
                        ActivityRow(symbol: w.symbol, tint: Theme.strain[0], badge: (d.workoutStrain[w.id] ?? 0).oneDecimal, title: w.name,
                                    detail: "\(w.start.shortTime) · \(Int(w.duration / 60)) min")
                    }
                }
                if d.raw.sleep == nil && d.raw.workouts.isEmpty {
                    Text("No activities recorded.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func tonight(_ d: DayScores) -> some View {
        let need = ScoreEngine.sleepNeed(profile: store.profile, previousStrain: d.strain, debt: d.sleepDebt)
        let bedtime = ScoreEngine.recommendedBedtime(days: store.days, need: need)
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Tonight's Sleep")
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(bedtime?.shortTime ?? "–", systemImage: "moon.zzz")
                            .font(.system(.title, design: .rounded).weight(.semibold))
                        Text("Recommended bedtime").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(need.hoursMinutes)
                            .font(.system(.title, design: .rounded).weight(.semibold))
                        Text("Sleep needed").font(.caption2.weight(.semibold)).foregroundStyle(Theme.sleep[0])
                    }
                }
            }
        }
    }

    private var weekChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Strain & Recovery · 7 days")
                StrainRecoveryChart(days: store.window(7), compact: true).frame(height: 170)
            }
        }
    }

    @ViewBuilder private var bodyAgeTeaser: some View {
        if let age = store.bodyAge {
            NavigationLink(value: Route.bodyAge) {
                GlassCard(tint: Theme.green) {
                    HStack(spacing: 16) {
                        HaloOrb(palette: .recovery(80), energy: 0.2, speed: 0.45).frame(width: 56, height: 56).padding(4)
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(text: "Body Age")
                            BigNumber(text: age.bodyAge.oneDecimal, size: 28)
                            Text(age.difference <= 0 ? "\(abs(age.difference).oneDecimal) years younger" : "\(age.difference.oneDecimal) years older")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(age.difference <= 0 ? Theme.green : Theme.hurts)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("No data yet").font(.title3.weight(.semibold))
                Text(store.errorMessage ?? "Wear your Apple Watch through the day and to bed, then pull to refresh.")
                    .foregroundStyle(.secondary)
                Button("Use demo data") { store.source = .demo }.buttonStyle(.glass)
            }
        }
        .padding(.top, 60)
    }
}

// MARK: - Pieces

struct MetricCapsule: View {
    var progress: Double
    var color: Color
    var value: String
    var title: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 4)
                Circle().trim(from: 0, to: max(0.01, min(progress, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 19, weight: .medium)).monospacedDigit()
                Eyebrow(text: title)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }
}

struct RingTile: View {
    var progress: Double
    var colors: [Color]
    var value: String
    var unit: String?
    var title: String
    var marker: Double? = nil

    var body: some View {
        VStack(spacing: 10) {
            ScoreRing(progress: progress, colors: colors, lineWidth: 9, marker: marker) {
                BigNumber(text: value, unit: unit, size: 26)
            }
            .frame(width: 96, height: 96)
            HStack(spacing: 3) {
                Text(title).font(.caption.weight(.bold))
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
    }
}

struct ActivityRow: View {
    var symbol: String
    var tint: Color
    var badge: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(badge).monospacedDigit()
            }
            .font(.callout.weight(.bold))
            .frame(width: 92, height: 40)
            .background(tint.opacity(0.35), in: .rect(cornerRadius: 12))
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(6)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}

/// Health Monitor: overnight vitals compared to your own normal range.
enum HealthMonitor {
    struct Metric: Identifiable {
        var id: String { name }
        var name: String
        var symbol: String
        var value: String
        var range: String
        var inRange: Bool
        var low: Double? = nil      // band edges and value, for the range bar
        var high: Double? = nil
        var raw: Double? = nil
    }

    static func metrics(for d: DayScores) -> [Metric] {
        var out: [Metric] = []
        func add(_ name: String, _ symbol: String, _ value: Double?, _ base: Baseline?, _ format: (Double) -> String) {
            guard let value else { return }
            if let base {
                let lo = base.mean - 2 * base.sd, hi = base.mean + 2 * base.sd
                out.append(Metric(name: name, symbol: symbol, value: format(value), range: "\(format(lo))–\(format(hi))", inRange: (lo...hi).contains(value), low: lo, high: hi, raw: value))
            } else {
                out.append(Metric(name: name, symbol: symbol, value: format(value), range: "learning", inRange: true))
            }
        }
        if let hrv = d.raw.hrv, let b = d.hrvBaseline {
            let lo = exp(b.mean - 2 * b.sd), hi = exp(b.mean + 2 * b.sd)
            out.append(Metric(name: "Heart Rate Variability", symbol: "waveform.path.ecg", value: "\(Int(hrv)) ms", range: "\(Int(lo))–\(Int(hi))", inRange: (lo...hi).contains(hrv), low: lo, high: hi, raw: hrv))
        }
        add("Resting Heart Rate", "heart", d.raw.restingHR, d.rhrBaseline) { "\(Int($0.rounded()))" }
        add("Respiratory Rate", "lungs", d.raw.respiratoryRate, d.respBaseline) { $0.oneDecimal }
        if let spo2 = d.raw.spo2 {
            out.append(Metric(name: "Blood Oxygen", symbol: "drop", value: "\(Int(spo2 * 100))%", range: "95–100%", inRange: spo2 >= 0.94))
        }
        if let temp = d.raw.wristTemperature {
            if let b = d.tempBaseline {
                let delta = temp - b.mean
                out.append(Metric(name: "Skin Temperature", symbol: "thermometer.medium", value: String(format: "%+.1f°", delta), range: "±0.5°", inRange: abs(delta) <= 0.5, low: -0.5, high: 0.5, raw: delta))
            } else {
                out.append(Metric(name: "Skin Temperature", symbol: "thermometer.medium", value: String(format: "%.1f°", temp), range: "learning", inRange: true))
            }
        }
        return out
    }
}

struct HealthMonitorView: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        DetailScaffold(title: "Body check", accent: Theme.green) {
            if let d = store.selected {
                let metrics = HealthMonitor.metrics(for: d)
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(metrics) { m in
                            HStack(spacing: 12) {
                                Image(systemName: m.symbol).frame(width: 26).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).font(.footnote.weight(.semibold))
                                    Text("Your range \(m.range)").font(.caption).foregroundStyle(.secondary)
                                    if let lo = m.low, let hi = m.high, let v = m.raw {
                                        RangeBar(low: lo, high: hi, value: v, inRange: m.inRange)
                                            .frame(maxWidth: 150)
                                            .padding(.top, 4)
                                    }
                                }
                                Spacer()
                                Text(m.value).font(.system(.title3, design: .rounded).weight(.semibold))
                                Image(systemName: m.inRange ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(m.inRange ? Theme.green : Theme.yellow)
                            }
                            .padding(.vertical, 12)
                            if m.id != metrics.last?.id { Divider().opacity(0.4) }
                        }
                    }
                }
                InsightCallout(text: "Ranges are your personal 30-day normal (±2 standard deviations), leaving out days you marked sick or travel. Two or more vitals out of range at once brings up the Body check alert on Today.")
            }
        }
    }
}

/// Your value against your normal band (the middle half of the bar).
struct RangeBar: View {
    var low: Double
    var high: Double
    var value: Double
    var inRange: Bool

    var body: some View {
        GeometryReader { geo in
            let span = max(high - low, 0.0001)
            let lo = low - span * 0.5, hi = high + span * 0.5
            let x = ((value - lo) / (hi - lo)).clamped(0, 1) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.primary.opacity(0.18))
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: geo.size.width * 0.25)
                Circle().fill(inRange ? Color.primary : Theme.hurts)
                    .frame(width: 10, height: 10)
                    .offset(x: x - 5)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Morning check-in: a 1-minute HRV read from a Breathe session on the watch, how ready you feel, and today's status.
struct CheckInView: View {
    @Environment(MetricsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var readiness: Int?
    @State private var status: DayStatus = .normal
    @State private var rmssd: Double?
    @State private var beats: Int?
    @State private var reading = false
    @State private var readError: String?
    private let words = ["Drained", "Low", "Okay", "Good", "Sharp"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sit still and run a 1-minute Breathe session in the Mindfulness app on your watch. Then read it here.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button {
                        Task { await read() }
                    } label: {
                        HStack {
                            Label(reading ? "Reading…" : "Read morning HRV", systemImage: "waveform.path.ecg")
                            Spacer()
                            if let rmssd {
                                Text("\(Int(rmssd.rounded())) ms").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(reading)
                    if let beats, rmssd != nil {
                        Text("From \(beats) clean beats").font(.caption).foregroundStyle(.secondary)
                    }
                    if let readError {
                        Text(readError).font(.caption).foregroundStyle(Theme.hurts)
                    }
                } header: {
                    Text("Morning HRV")
                }

                Section("How ready do you feel?") {
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { n in
                            Button {
                                readiness = n
                            } label: {
                                VStack(spacing: 2) {
                                    Text("\(n)").font(.title3.weight(.semibold))
                                    Text(words[n - 1]).font(.caption2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                            }
                            .buttonStyle(.bordered)
                            .tint(readiness == n ? Color.primary : Color.secondary)
                        }
                    }
                }

                Section {
                    Picker("Today", selection: $status) {
                        ForEach(DayStatus.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Today is")
                } footer: {
                    Text("Sick and travel days stay out of your normal ranges, so one rough day can't move your baseline. Tag yesterday's habits in the Journal tab.")
                }
            }
            .navigationTitle("Morning check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            let entry = store.dayLog(for: .now)
            readiness = entry.readiness
            status = entry.status ?? .normal
            rmssd = entry.morningRMSSD
            beats = entry.morningBeats
        }
    }

    private func read() async {
        reading = true
        readError = nil
        defer { reading = false }
        if let result = await store.readMorningHRV() {
            rmssd = result.rmssd
            beats = result.beats
        } else {
            readError = "No clean reading from the last 3 hours. Run a Breathe session on the watch, wait a minute for it to sync, then try again."
        }
    }

    private func save() {
        let r = readiness, st = status, hrv = rmssd, b = beats
        store.updateDayLog(for: .now) { entry in
            entry.readiness = r
            entry.status = st
            entry.morningRMSSD = hrv
            entry.morningBeats = b
            entry.checkedInAt = .now
        }
    }
}
