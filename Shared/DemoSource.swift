import Foundation

/// Realistic synthetic data so the app can be explored in the Simulator or without a watch.
/// Deterministic: the same day always produces the same numbers.
final class DemoSource: HealthDataSource {
    private let cal = Calendar.current

    func requestAuthorization() async throws {}
    func profileHints() -> (age: Int?, sex: Sex?) { (31, .male) }

    func loadDays(count: Int, detailedDays: Int) async throws -> [RawDay] {
        let today = cal.startOfDay(for: .now)
        return (0..<count).map { i in
            let day = cal.date(byAdding: .day, value: i - count + 1, to: today)!
            return makeDay(day, detailed: i >= count - detailedDays, isToday: day == today)
        }
    }

    private func makeDay(_ day: Date, detailed: Bool, isToday: Bool) -> RawDay {
        var rng = SeededRandom(seed: UInt64(day.timeIntervalSinceReferenceDate / 86400))
        let weekday = cal.component(.weekday, from: day)
        let fitnessTrend = Double(cal.ordinality(of: .day, in: .era, for: day) ?? 0).truncatingRemainder(dividingBy: 60) / 60

        // Night
        let bedHour = 22.8 + rng.normal() * 0.6 + (weekday == 7 || weekday == 1 ? 0.8 : 0)
        let sleepHours = (7.2 + rng.normal() * 0.8).clamped(4.8, 9.3)
        let bed = day.addingTimeInterval((bedHour - 24) * 3600)
        let sleep = makeSleep(start: bed, hours: sleepHours, rng: &rng)

        var raw = RawDay(date: day)
        raw.sleep = sleep
        let readiness = rng.normal() + (sleepHours - 7.2) * 0.6
        raw.hrv = (52 + readiness * 9 + fitnessTrend * 6).clamped(22, 110)
        raw.hrvSampleCount = 3 + Int((rng.normal() + 1.5).clamped(0, 4))
        raw.restingHR = (54 - readiness * 2.2 - fitnessTrend * 2).clamped(44, 70)
        raw.respiratoryRate = 14.6 + rng.normal() * 0.4
        raw.wristTemperature = 34.9 + rng.normal() * 0.15
        raw.spo2 = (0.965 + rng.normal() * 0.008).clamped(0.92, 1)
        raw.vo2Max = 46 + fitnessTrend * 2.5

        // Day
        let hasRun = [2, 4, 7].contains(weekday)
        let hasLift = [3, 5].contains(weekday)
        let wake = sleep.end
        let currentMinute = isToday ? max(0, Int(Date.now.timeIntervalSince(day) / 60)) : 24 * 60
        raw.steps = (hasRun ? 12_500 : 7_800) + rng.normal() * 1500
        raw.activeEnergy = raw.steps * 0.045 + (hasRun ? 450 : hasLift ? 280 : 0)

        var workouts: [WorkoutSummary] = []
        if hasRun {
            let start = day.addingTimeInterval((7.2 + rng.uniform() * 0.5) * 3600)
            workouts.append(WorkoutSummary(name: "Running", symbol: "figure.run", start: start, end: start.addingTimeInterval((38 + rng.uniform() * 20) * 60), isStrength: false, energyKcal: 480))
        }
        if hasLift {
            let start = day.addingTimeInterval((18 + rng.uniform()) * 3600)
            workouts.append(WorkoutSummary(name: "Strength", symbol: "figure.strengthtraining.traditional", start: start, end: start.addingTimeInterval(55 * 60), isStrength: true, energyKcal: 310))
        }
        if weekday == 1 {
            let start = day.addingTimeInterval(10.5 * 3600)
            workouts.append(WorkoutSummary(name: "Cycling", symbol: "figure.outdoor.cycle", start: start, end: start.addingTimeInterval(95 * 60), isStrength: false, energyKcal: 820))
        }
        raw.workouts = workouts.filter { $0.start.timeIntervalSince(day) / 60 < Double(currentMinute) }

        if detailed {
            raw.heartRate = makeHeartRate(day: day, sleep: sleep, wake: wake, rhr: raw.restingHR ?? 55, workouts: raw.workouts, upTo: currentMinute, rng: &rng)
        }
        if isToday {
            raw.steps *= Double(currentMinute) / 1440
            raw.activeEnergy *= Double(currentMinute) / 1440
        }
        return raw
    }

    private func makeSleep(start: Date, hours: Double, rng: inout SeededRandom) -> SleepSession {
        var segments: [SleepSegment] = []
        var t = start
        let end = start.addingTimeInterval(hours * 3600 * 1.07)
        var cycle = 0
        while t < end {
            let plan: [(SleepStage, Double)] = [
                (.core, 20 + rng.uniform() * 15),
                (.deep, max(5, (cycle < 2 ? 35 : 10) + rng.normal() * 6)),
                (.core, 15 + rng.uniform() * 10),
                (.rem, (cycle < 2 ? 12 : 28) + rng.normal() * 5),
                (.awake, rng.uniform() < 0.4 ? 2 + rng.uniform() * 6 : 0),
            ]
            for (stage, minutes) in plan where minutes > 0 && t < end {
                let next = min(t.addingTimeInterval(minutes * 60), end)
                segments.append(SleepSegment(stage: stage, start: t, end: next))
                t = next
            }
            cycle += 1
        }
        return SleepSession(segments: segments)
    }

    private func makeHeartRate(day: Date, sleep: SleepSession, wake: Date, rhr: Double, workouts: [WorkoutSummary], upTo minute: Int, rng: inout SeededRandom) -> [HeartRatePoint] {
        var points: [HeartRatePoint] = []
        var drift = 0.0
        for m in stride(from: 0, to: min(minute, 1440), by: 1) {
            let t = day.addingTimeInterval(Double(m) * 60)
            drift = drift * 0.9 + rng.normal() * 1.5
            var bpm: Double
            if let w = workouts.first(where: { $0.start <= t && t <= $0.end }) {
                let progress = t.timeIntervalSince(w.start) / w.duration
                let base = w.isStrength ? 118.0 : w.name == "Cycling" ? 138 : 152
                bpm = base + 18 * sin(progress * .pi) + rng.normal() * (w.isStrength ? 14 : 5)
            } else if t < wake || t >= sleep.start.addingTimeInterval(86400) {
                bpm = rhr - 3 + drift * 0.5
            } else {
                let hour = Double(m) / 60
                let busy = (9...12).contains(hour) || (14...17).contains(hour) ? 24.0 : 14
                bpm = rhr + busy + max(drift, -6) * 2
                if (8.4...8.8).contains(hour) || (18.2...18.6).contains(hour) { bpm = rhr + 48 + drift }   // walking commute
                if rng.uniform() < 0.02 { bpm += 25 }   // stairs, a coffee, a meeting
            }
            // Outside workouts and sleep the watch only samples every ~5 minutes.
            let sampled = workouts.contains { $0.start <= t && t <= $0.end } || m % 5 == 0
            if sampled { points.append(HeartRatePoint(date: t, bpm: bpm.clamped(40, 200))) }
        }
        return points
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }

    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }

    mutating func uniform() -> Double { Double(next() % 1_000_000) / 1_000_000 }

    /// Standard normal via Box–Muller.
    mutating func normal() -> Double {
        let u1 = max(uniform(), 1e-9), u2 = uniform()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
