import SwiftUI

@main
struct PulsrWatchApp: App {
    @State private var store = MetricsStore(historyDays: 30, detailedDays: 2)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
                .task { await store.connect() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.load() } }
                }
        }
    }
}

struct WatchRootView: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        let d = store.today
        TabView {
            SummaryPage(day: d)
                .containerBackground(Theme.recoveryColor(d?.recovery).opacity(0.35).gradient, for: .tabView)
            RecoveryPage(day: d)
                .containerBackground(Theme.recoveryColor(d?.recovery).opacity(0.3).gradient, for: .tabView)
            StrainPage(day: d)
                .containerBackground(Theme.strain[1].opacity(0.35).gradient, for: .tabView)
            SleepPage(day: d)
                .containerBackground(Theme.sleep[1].opacity(0.35).gradient, for: .tabView)
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct SummaryPage: View {
    var day: DayScores?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                HaloOrb(palette: .recovery(day?.recovery), forceDark: true)
                    .frame(width: 92, height: 92)
            }
            .frame(width: 104, height: 96)
            VStack(spacing: 0) {
                Text(day?.recovery.map { "\($0.percent)%" } ?? "–")
                    .font(.system(size: 30, weight: .thin))
                Text("Recovery").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text("Sleep ").foregroundStyle(.secondary) + Text(day?.sleepPerformance.map { "\($0.percent)%" } ?? "–").foregroundStyle(Theme.sleep[0])
                Text("Strain ").foregroundStyle(.secondary) + Text(day?.strain.oneDecimal ?? "–").foregroundStyle(Theme.strain[0])
            }
            .font(.system(size: 12, weight: .medium))
        }
        .navigationTitle("Nine30")
    }

    private func mini(progress: Double, colors: [Color], value: String, title: String) -> some View {
        VStack(spacing: 2) {
            ScoreRing(progress: progress, colors: colors, lineWidth: 5) {
                Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).minimumScaleFactor(0.7)
            }
            .frame(width: 50, height: 50)
            Text(title).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}

private struct RecoveryPage: View {
    var day: DayScores?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let day {
                    Text(Insights.headline(day).title).font(.headline)
                    row("HRV", day.raw.hrv.map { "\(Int($0)) ms" })
                    row("Resting HR", day.raw.restingHR.map { "\(Int($0)) bpm" })
                    row("Resp. rate", day.raw.respiratoryRate?.oneDecimal)
                    let target = ScoreEngine.strainTarget(recovery: day.recovery)
                    row("Strain target", "\(Int(target.lowerBound))–\(Int(target.upperBound))")
                } else {
                    Text("Wear your watch to sleep to get your first Recovery.").font(.footnote)
                }
            }
        }
        .navigationTitle("Recovery")
    }
}

private struct StrainPage: View {
    var day: DayScores?

    var body: some View {
        VStack(spacing: 6) {
            ScoreRing(progress: (day?.strain ?? 0) / 21, colors: Theme.strain, lineWidth: 8,
                      marker: ScoreEngine.strainTarget(recovery: day?.recovery).lowerBound / 21) {
                Text(day?.strain.oneDecimal ?? "–").font(.system(size: 28, weight: .bold, design: .rounded))
            }
            .frame(width: 100, height: 100)
            if let day {
                row("Zones 4–5", (day.zoneMinutes[4...5].reduce(0, +) * 60).hoursMinutes)
                row("Steps", day.raw.steps.formatted(.number.precision(.fractionLength(0))))
            }
        }
        .navigationTitle("Strain")
    }
}

private struct SleepPage: View {
    var day: DayScores?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let day, let sleep = day.raw.sleep {
                Text(sleep.asleep.hoursMinutes).font(.system(size: 34, weight: .bold, design: .rounded))
                Text("of \(day.sleepNeed.hoursMinutes) needed").font(.footnote).foregroundStyle(.secondary)
                row("Performance", day.sleepPerformance.map { "\($0.percent)%" })
                row("Deep + REM", sleep.restorativeShare.map { "\(Int($0 * 100))%" })
            } else {
                Text("No sleep recorded last night.").font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle("Sleep")
    }
}

private func row(_ title: String, _ value: String?) -> some View {
    HStack {
        Text(title).font(.footnote).foregroundStyle(.secondary)
        Spacer()
        Text(value ?? "–").font(.system(.body, design: .rounded).weight(.semibold))
    }
}
