import SwiftUI

struct Behavior: Identifiable, Hashable {
    var id: String
    var title: String
    var symbol: String

    static let all: [Behavior] = [
        .init(id: "trading_day", title: "Trading day", symbol: "chart.line.uptrend.xyaxis"),
        .init(id: "big_loss_day", title: "Big loss day", symbol: "arrow.down.right"),
        .init(id: "alcohol", title: "Alcohol", symbol: "wineglass"),
        .init(id: "caffeine_late", title: "Caffeine after 2 PM", symbol: "cup.and.saucer"),
        .init(id: "late_meal", title: "Late meal", symbol: "fork.knife"),
        .init(id: "hydrated", title: "Well hydrated", symbol: "drop"),
        .init(id: "phone_in_bed", title: "Phone in bed", symbol: "iphone"),
        .init(id: "read_in_bed", title: "Read in bed", symbol: "book"),
        .init(id: "meditation", title: "Meditation", symbol: "brain.head.profile"),
        .init(id: "stretching", title: "Stretching / mobility", symbol: "figure.flexibility"),
        .init(id: "morning_light", title: "Morning sunlight", symbol: "sun.max"),
        .init(id: "sauna", title: "Sauna", symbol: "flame"),
        .init(id: "cold", title: "Cold exposure", symbol: "snowflake"),
        .init(id: "work_late", title: "Worked late", symbol: "laptopcomputer"),
        .init(id: "magnesium", title: "Magnesium", symbol: "pills"),
    ]
}

/// Yes/no answers per day, stored as JSON in Application Support.
@MainActor
@Observable
final class JournalStore {
    private(set) var entries: [String: [String: Bool]] = [:]   // "yyyy-MM-dd" → behavior → answer

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: [String: Bool]].self, from: data) {
            entries = decoded
        }
    }

    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func answer(_ behavior: String, on date: Date) -> Bool? { entries[Self.key(date)]?[behavior] }

    func set(_ behavior: String, on date: Date, to value: Bool?) {
        entries[Self.key(date), default: [:]][behavior] = value
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }

    struct Impact: Identifiable {
        var id: String { behavior.id }
        var behavior: Behavior
        var points: Double     // change in next-day Recovery, in points, after adjusting for that day's strain
        var low: Double        // about a 95% range for the true effect
        var high: Double
        var yes: Int
        var no: Int
        var isClear: Bool { low > 0 || high < 0 }
    }

    static let minimumDays = 10

    /// Next-day Recovery after "yes" vs "no" days. The day's strain is regressed out first, so a habit that tends to land
    /// on hard training days isn't blamed for the training. Needs 10+ days on each side. Correlation, not cause.
    func impacts(days: [DayScores], demo: Bool) -> [Impact] {
        let source = demo ? Self.demoEntries(days: days) : entries
        let cal = Calendar.current
        let recoveryByKey = Dictionary(days.compactMap { d in d.recovery.map { (Self.key(d.date), $0) } }, uniquingKeysWith: { a, _ in a })
        var keys: [String] = [], strains: [Double] = [], nexts: [Double] = []
        for d in days {
            guard let next = cal.date(byAdding: .day, value: 1, to: d.date), let r = recoveryByKey[Self.key(next)] else { continue }
            keys.append(Self.key(d.date)); strains.append(d.strain); nexts.append(r)
        }
        guard keys.count >= 2 * Self.minimumDays else { return [] }
        let n = Double(keys.count)
        let mx = strains.reduce(0, +) / n, my = nexts.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for i in keys.indices {
            sxx += (strains[i] - mx) * (strains[i] - mx)
            sxy += (strains[i] - mx) * (nexts[i] - my)
        }
        let slope = sxx > 0 ? sxy / sxx : 0
        var residual: [String: Double] = [:]
        for i in keys.indices { residual[keys[i]] = nexts[i] - (my + slope * (strains[i] - mx)) }

        return Behavior.all.compactMap { behavior -> Impact? in
            var yes: [Double] = [], no: [Double] = []
            for (key, r) in residual {
                guard let answer = source[key]?[behavior.id] else { continue }
                if answer { yes.append(r) } else { no.append(r) }
            }
            guard yes.count >= Self.minimumDays, no.count >= Self.minimumDays else { return nil }
            let meanYes = yes.reduce(0, +) / Double(yes.count), meanNo = no.reduce(0, +) / Double(no.count)
            let varYes = yes.map { ($0 - meanYes) * ($0 - meanYes) }.reduce(0, +) / Double(yes.count - 1)
            let varNo = no.map { ($0 - meanNo) * ($0 - meanNo) }.reduce(0, +) / Double(no.count - 1)
            let diff = meanYes - meanNo
            let se = (varYes / Double(yes.count) + varNo / Double(no.count)).squareRoot()
            let t = 2.0   // about 95% with 10–30 days a side; a touch conservative beyond that
            return Impact(behavior: behavior, points: diff, low: diff - t * se, high: diff + t * se, yes: yes.count, no: no.count)
        }
        .sorted { $0.points > $1.points }
    }

    /// Plausible answers for demo mode, correlated with the following day's recovery.
    static func demoEntries(days: [DayScores]) -> [String: [String: Bool]] {
        let effects: [String: Double] = ["alcohol": -18, "caffeine_late": -8, "late_meal": -6, "hydrated": 12, "phone_in_bed": -3,
                                         "read_in_bed": 7, "meditation": 5, "stretching": 3, "morning_light": 4, "sauna": 6,
                                         "cold": 1, "work_late": -6, "magnesium": 2]
        var out: [String: [String: Bool]] = [:]
        for (i, d) in days.enumerated() where i + 1 < days.count {
            guard let next = days[i + 1].recovery else { continue }
            var rng = SeededRandom(seed: UInt64(i * 7919 + 13))
            var answers: [String: Bool] = [:]
            for (id, effect) in effects {
                let p = 0.4 + (next - 55) / 100 * (effect / 20)
                answers[id] = rng.uniform() < p.clamped(0.08, 0.92)
            }
            out[key(d.date)] = answers
        }
        return out
    }
}

struct JournalView: View {
    @Environment(MetricsStore.self) private var store
    @Environment(JournalStore.self) private var journal

    private var date: Date { store.selected?.date ?? Calendar.current.startOfDay(for: .now) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Journal").font(.largeTitle.weight(.bold))
                        Text(store.isToday ? "What did you do today?" : "Entries for \(date.dayLabel)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.top, 8)

                NavigationLink(value: Route.journalInsights) {
                    GlassCard(tint: Color(hex: 0x6E7BFF)) {
                        HStack(spacing: 14) {
                            Image(systemName: "chart.bar.xaxis").font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Recovery Impact").font(.headline)
                                Text("See which habits help or hurt your recovery").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(Behavior.all) { b in
                            BehaviorRow(behavior: b, answer: journal.answer(b.id, on: date)) { value in
                                withAnimation(.snappy) { journal.set(b.id, on: date, to: value) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground(accent: Color(hex: 0x6E7BFF), secondary: Theme.green) }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct BehaviorRow: View {
    var behavior: Behavior
    var answer: Bool?
    var onChange: (Bool?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: behavior.symbol).frame(width: 26).foregroundStyle(.secondary)
            Text(behavior.title).font(.callout.weight(.medium))
            Spacer()
            choice("No", selected: answer == false, color: .primary) { onChange(answer == false ? nil : false) }
            choice("Yes", selected: answer == true, color: Theme.green) { onChange(answer == true ? nil : true) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func choice(_ title: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .frame(width: 44, height: 30)
                .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                .background(selected ? color : Color.primary.opacity(0.08), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

struct JournalInsightsView: View {
    @Environment(MetricsStore.self) private var store
    @Environment(JournalStore.self) private var journal

    var body: some View {
        let impacts = journal.impacts(days: Array(store.days.suffix(90)), demo: store.source == .demo)
        DetailScaffold(title: "Journal Insights", accent: Color(hex: 0x6E7BFF)) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Refreshed daily")
                Text("Recovery Impact Analysis").font(.title2.weight(.semibold))
                Text("Next-day Recovery after each tag, in points, with the range the true effect likely falls in. Adjusted for that day's strain.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)

            HStack {
                Label("Hurts", systemImage: "arrowtriangle.down.fill").foregroundStyle(Theme.hurts)
                Spacer()
                Text("Impact").foregroundStyle(.secondary)
                Spacer()
                Label("Helps", systemImage: "arrowtriangle.up.fill").foregroundStyle(Theme.helps)
            }
            .font(.caption.weight(.bold))

            if impacts.isEmpty {
                GlassCard {
                    Text("Answer the journal for a few weeks. Each tag needs at least 10 “yes” and 10 “no” days before it shows a number.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(impacts) { impact in
                ImpactRow(impact: impact)
            }
            if !impacts.isEmpty {
                InsightCallout(text: "Gray rows are not clear yet: their range still crosses zero. Correlation, not cause: a big loss day may also be a short-sleep day.")
            }
        }
    }
}

struct ImpactRow: View {
    var impact: JournalStore.Impact

    var body: some View {
        let color: Color = !impact.isClear ? .secondary : impact.points >= 0 ? Theme.helps : Theme.hurts
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(impact.behavior.title).font(.footnote.weight(.semibold))
                    Text("\(impact.yes) yes · \(impact.no) no" + (impact.isClear ? "" : " · not clear yet"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%+.0f pts", impact.points))
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(color)
            }
            ImpactRangeBar(points: impact.points, low: impact.low, high: impact.high, color: color)
                .frame(height: 14)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

/// Effect in points on a −25…+25 axis: the dot is the estimate, the bar the likely range, the tick is zero.
struct ImpactRangeBar: View {
    var points: Double
    var low: Double
    var high: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let limit = 25.0
            let w = geo.size.width
            let x: (Double) -> CGFloat = { v in CGFloat(((v + limit) / (2 * limit)).clamped(0, 1)) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.06)).frame(height: 6).offset(y: 4)
                Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1, height: 14).offset(x: x(0))
                Capsule().fill(color.opacity(0.45))
                    .frame(width: max(x(high) - x(low), 4), height: 6)
                    .offset(x: x(low), y: 4)
                Circle().fill(color).frame(width: 12, height: 12).offset(x: x(points) - 6, y: 1)
            }
        }
        .accessibilityHidden(true)
    }
}
