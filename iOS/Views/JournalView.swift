import SwiftUI

struct Behavior: Identifiable, Hashable {
    var id: String
    var title: String
    var symbol: String

    static let all: [Behavior] = [
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
        var percent: Double   // change in next-day recovery when "yes"
        var samples: Int
    }

    /// Compares next-day recovery after "yes" vs "no" days. Needs at least 3 of each.
    func impacts(days: [DayScores], demo: Bool) -> [Impact] {
        let source = demo ? Self.demoEntries(days: days) : entries
        let recoveryByKey = Dictionary(days.compactMap { d in d.recovery.map { (Self.key(d.date), $0) } }, uniquingKeysWith: { a, _ in a })
        let cal = Calendar.current
        return Behavior.all.compactMap { b in
            var yes: [Double] = [], no: [Double] = []
            for d in days {
                guard let answer = source[Self.key(d.date)]?[b.id],
                      let next = cal.date(byAdding: .day, value: 1, to: d.date),
                      let recovery = recoveryByKey[Self.key(next)] else { continue }
                if answer { yes.append(recovery) } else { no.append(recovery) }
            }
            guard yes.count >= 3, no.count >= 3 else { return nil }
            let my = yes.reduce(0, +) / Double(yes.count), mn = no.reduce(0, +) / Double(no.count)
            return Impact(behavior: b, percent: (my - mn) / max(mn, 1) * 100, samples: yes.count + no.count)
        }
        .sorted { $0.percent > $1.percent }
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
                Text("How each behavior changed your next-day Recovery over the past 90 days.")
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
                    Text("Answer the journal for a few weeks — each behavior needs at least 3 “yes” and 3 “no” days to show its impact.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(impacts) { impact in
                ImpactRow(impact: impact)
            }
        }
    }
}

struct ImpactRow: View {
    var impact: JournalStore.Impact

    var body: some View {
        let color = impact.percent >= 0 ? Theme.helps : Theme.hurts
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(impact.behavior.title).font(.footnote.weight(.semibold))
                Spacer()
                Text(String(format: "%+.0f%%", impact.percent))
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(abs(impact.percent) < 2 ? Color.secondary : color)
            }
            GeometryReader { geo in
                let half = geo.size.width / 2
                let w = min(half, half * abs(impact.percent) / 25)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(abs(impact.percent) < 2 ? .gray : color)
                        .frame(width: max(w, 4))
                        .offset(x: impact.percent >= 0 ? half : half - w)
                    Circle().fill(Color.primary).frame(width: 6, height: 6).offset(x: half - 3)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
