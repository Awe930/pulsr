import Foundation

/// Plain-language explanations generated from the scores. Shared by the phone and the watch.
enum Insights {
    static func hrvBaselineValue(_ d: DayScores) -> Double? { d.hrvBaseline.map { exp($0.mean) } }

    static func hrvChange(_ d: DayScores) -> Double? {
        guard let hrv = d.raw.hrv, let base = hrvBaselineValue(d) else { return nil }
        return (hrv - base) / base
    }

    static func headline(_ d: DayScores) -> (title: String, body: String) {
        if d.status == .sick {
            return ("Rest day", "You marked today as sick. Keep Strain under 8, drink water and get to bed early. Today stays out of your normal ranges.")
        }
        guard let recovery = d.recovery else {
            return ("Waiting for tonight", "Wear your Apple Watch to sleep. Recovery appears once there is overnight heart rate variability.")
        }
        let target = ScoreEngine.strainTarget(recovery: recovery)
        let targetText = "\(Int(target.lowerBound))–\(Int(target.upperBound))"
        var hrvText = ""
        if let trend = d.hrvTrend, let range = d.hrvRange, let status = d.hrvStatus {
            let where_ = status == .typical ? "inside" : status == .below ? "below" : "above"
            hrvText = "Your 7-day HRV is \(Int(trend.rounded())) ms, \(where_) your range (\(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded()))). "
        } else if let change = hrvChange(d) {
            let pct = Int(abs(change * 100).rounded())
            hrvText = change >= 0 ? "Your HRV is \(pct)% above your baseline. " : "Your HRV is \(pct)% below your baseline. "
        }
        var calibrating = d.isCalibrating ? " Nine30 is still learning your baseline, so expect scores to settle over the first week." : ""
        if d.status == .travel { calibrating += " Travel day: left out of your normal ranges." }
        switch RecoveryZone(recovery) {
        case .green:
            return ("Primed to perform", hrvText + "Your body can take on significant exertion — aim for a Strain of \(targetText)." + calibrating)
        case .yellow:
            return ("Maintaining", hrvText + "You are functioning normally. A moderate Strain of \(targetText) keeps you progressing without digging a hole." + calibrating)
        case .red:
            return ("Prioritize recovery", hrvText + "Your body is asking for rest. Keep Strain around \(targetText), hydrate, and get to bed early." + calibrating)
        }
    }

    static func sleepSummary(_ d: DayScores) -> String {
        guard let perf = d.sleepPerformance, let sleep = d.raw.sleep else { return "No sleep recorded for this night. Wear your watch to bed with Sleep Focus on." }
        let weakest = [("Hours vs needed", d.hoursVsNeeded), ("Sleep consistency", d.sleepConsistency), ("Sleep efficiency", d.sleepEfficiency)]
            .compactMap { name, v in v.map { (name, $0) } }
            .min { $0.1 < $1.1 }
        let quality = perf >= 85 ? "optimal" : perf >= 70 ? "sufficient" : "poor"
        var text = "You slept \(sleep.asleep.hoursMinutes) of the \(d.sleepNeed.hoursMinutes) you needed — performance is \(quality)."
        if let weakest, weakest.1 < 0.85 { text += " \(weakest.0) has the most room to improve." }
        return text
    }

    static func strainSummary(_ d: DayScores) -> String {
        switch d.strain {
        case ..<10: "Strain under 10 is light — good for active recovery days."
        case ..<14: "Strain between 10 and 14 is moderate, building fitness while leaving room to recover."
        case ..<18: "Strain between 14 and 17.9 is strenuous — your cardiovascular system has been working hard."
        default: "Strain of 18+ is all out. Make tonight's sleep a priority."
        }
    }

    static func stressSummary(_ d: DayScores) -> String {
        let awake = d.stress.filter { p in !(d.raw.sleep.map { $0.start <= p.date && p.date <= $0.end } ?? false) }
        guard !awake.isEmpty else { return "No daytime heart rate yet. Stress is estimated from heart rate relative to your resting baseline." }
        let low = awake.filter { $0.level < 1 }.count, high = awake.filter { $0.level >= 2 }.count
        var text = low * 2 >= awake.count ? "Most of your day was spent in the low stress zone." : "A good part of your day was in elevated stress."
        // longest high streak
        var best = (start: Date?.none, length: 0), run = (start: Date?.none, length: 0)
        for p in awake {
            if p.level >= 2 { run = (run.start ?? p.date, run.length + 1); if run.length > best.length { best = run } }
            else { run = (nil, 0) }
        }
        if let start = best.start, high > 0 {
            text += " Your longest high-stress period started at \(start.shortTime) and lasted \(best.length * 15) minutes."
        }
        return text
    }

    /// Short context passed to the on-device coach model.
    static func coachContext(days: [DayScores], bodyAge: BodyAgeResult?, profile: UserProfile) -> String {
        guard let d = days.last else { return "No data yet." }
        var lines = ["User: \(profile.age) years old, \(profile.sex.rawValue)."]
        if let r = d.recovery { lines.append("Today's recovery: \(Int(r))%.") }
        if let hrv = d.raw.hrv, let base = hrvBaselineValue(d) { lines.append("HRV \(Int(hrv)) ms (baseline \(Int(base)) ms).") }
        if let rhr = d.raw.restingHR { lines.append("Resting HR \(Int(rhr)) bpm.") }
        if let s = d.raw.sleep { lines.append("Slept \(s.asleep.hoursMinutes) h, sleep performance \(Int(d.sleepPerformance ?? 0))%, need \(d.sleepNeed.hoursMinutes) h.") }
        lines.append("Strain so far today: \(d.strain.oneDecimal) of 21.")
        let week = days.suffix(7)
        lines.append("Last 7 days recovery: " + week.map { $0.recovery.map { "\(Int($0))" } ?? "-" }.joined(separator: ", ") + ".")
        lines.append("Last 7 days strain: " + week.map { $0.strain.oneDecimal }.joined(separator: ", ") + ".")
        for w in d.raw.workouts { lines.append("Workout today: \(w.name), \(Int(w.duration / 60)) min.") }
        if let vo2 = d.raw.vo2Max { lines.append("VO2 max \(vo2.oneDecimal).") }
        if let bodyAge { lines.append("Estimated body age \(bodyAge.bodyAge.oneDecimal) vs real age \(Int(bodyAge.chronological)).") }
        return lines.joined(separator: " ")
    }
}

// MARK: - Focus windows and energy (Nine30)

struct LevelPoint: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var level: Double   // 0...1 for alertness, 0...100 for energy
}

/// Predicted energy schedule for a day, anchored on when you woke up (a RISE-style heuristic, not a measurement).
struct EnergySchedule {
    var wake: Date
    var grogginessEnds: Date
    var peak: DateInterval
    var dip: DateInterval
    var secondWind: DateInterval
    var windDown: Date
    var bedtime: Date

    /// Predicted alertness, 0...1: sleep inertia after waking, a late-morning peak, an early-afternoon dip, an evening second wind.
    func alertness(at t: Date) -> Double {
        let h = t.timeIntervalSince(wake) / 3600
        guard h >= 0 else { return 0.1 }
        func g(_ m: Double, _ s: Double) -> Double { exp(-pow(h - m, 2) / (2 * s * s)) }
        let peakMid = peak.start.addingTimeInterval(peak.duration / 2).timeIntervalSince(wake) / 3600
        let dipMid = dip.start.addingTimeInterval(dip.duration / 2).timeIntervalSince(wake) / 3600
        let windMid = secondWind.start.addingTimeInterval(secondWind.duration / 2).timeIntervalSince(wake) / 3600
        let inertia = grogginessEnds.timeIntervalSince(wake) / 3600
        var v = 0.38 + 0.5 * g(peakMid, 1.4) + 0.28 * g(windMid, 1.3) - 0.2 * g(dipMid, 0.8)
        v -= 0.4 * exp(-h / max(inertia / 2.2, 0.3))
        v -= 0.05 * max(0, h - 13)
        return v.clamped(0.02, 1)
    }

    func curve(stepMinutes: Double = 15) -> [LevelPoint] {
        var out: [LevelPoint] = []
        var t = wake
        while t <= bedtime {
            out.append(LevelPoint(date: t, level: alertness(at: t)))
            t = t.addingTimeInterval(stepMinutes * 60)
        }
        return out
    }
}

enum Focus {
    /// The regular NYSE/CME cash session, 9:30–4:00 New York time, on weekdays (holidays not handled).
    static func marketSession(on day: Date) -> DateInterval? {
        var ny = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "America/New_York") else { return nil }
        ny.timeZone = zone
        let local = Calendar.current.dateComponents([.year, .month, .day], from: day)
        var open = DateComponents()
        open.year = local.year; open.month = local.month; open.day = local.day
        open.hour = 9; open.minute = 30
        var close = open
        close.hour = 16; close.minute = 0
        guard let o = ny.date(from: open), let c = ny.date(from: close) else { return nil }
        let weekday = ny.component(.weekday, from: o)
        guard weekday != 1, weekday != 7 else { return nil }
        return DateInterval(start: o, end: c)
    }

    /// Typical wake time (minutes after midnight) over the last 7 nights.
    static func typicalWakeMinutes(_ days: [DayScores]) -> Double? {
        let cal = Calendar.current
        let wakes = days.suffix(7).compactMap { $0.raw.sleep?.end }
        guard !wakes.isEmpty else { return nil }
        return wakes.map { Double(cal.component(.hour, from: $0) * 60 + cal.component(.minute, from: $0)) }.reduce(0, +) / Double(wakes.count)
    }

    /// Windows are offsets from wake: groggy ~75 min (longer with sleep debt), peak +2.5–5 h, dip +7–8.5 h, second wind +10.5–12.5 h.
    static func schedule(for day: DayScores, history: [DayScores], profile: UserProfile) -> EnergySchedule? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day.date)
        guard let typical = typicalWakeMinutes(history) else { return nil }
        let wake = day.raw.sleep?.end ?? dayStart.addingTimeInterval(typical * 60)
        func at(_ hours: Double) -> Date { wake.addingTimeInterval(hours * 3600) }
        let inertia = 1.25 + min(day.sleepDebt / 3600 * 0.25, 1.0)
        let need = ScoreEngine.sleepNeed(profile: profile, previousStrain: day.strain, debt: day.sleepDebt)
        let nextWake = cal.date(byAdding: .day, value: 1, to: dayStart)!.addingTimeInterval(typical * 60)
        let bedtime = nextWake.addingTimeInterval(-need / 0.92)
        return EnergySchedule(
            wake: wake,
            grogginessEnds: at(inertia),
            peak: DateInterval(start: at(2.5), end: at(5.0)),
            dip: DateInterval(start: at(7.0), end: at(8.5)),
            secondWind: DateInterval(start: at(10.5), end: at(12.5)),
            windDown: bedtime.addingTimeInterval(-3600),
            bedtime: bedtime)
    }

    /// One plain sentence on how the schedule meets the trading session.
    static func sessionNote(_ s: EnergySchedule, session: DateInterval?) -> String {
        guard let session else { return "No market session today. Use the peak for your hardest thinking." }
        var parts: [String] = []
        if let overlap = s.peak.intersection(with: session), overlap.duration >= 3600 {
            parts.append(overlap.start <= session.start.addingTimeInterval(1800) ? "Your peak lines up with the open." : "Your peak overlaps the morning session.")
        } else if s.peak.end <= session.start {
            parts.append("Your peak ends before the open, so the first hour may feel flatter.")
        } else {
            parts.append("Your peak falls later than the open.")
        }
        if let dipOverlap = s.dip.intersection(with: session), dipOverlap.duration >= 1800 {
            parts.append("The dip (\(s.dip.start.shortTime)–\(s.dip.end.shortTime)) lands inside the session: size down or step away then.")
        }
        return parts.joined(separator: " ")
    }

    struct MarketStress {
        var average: Double
        var peak: StressPoint
        var outsideAverage: Double?
    }

    /// Stress (0–3) during the session vs. the rest of the waking day.
    static func marketStress(_ d: DayScores, session: DateInterval?) -> MarketStress? {
        guard let session else { return nil }
        let awake = d.stress.filter { p in !(d.raw.sleep.map { $0.start <= p.date && p.date <= $0.end } ?? false) }
        let inside = awake.filter { session.contains($0.date) }
        guard let peak = inside.max(by: { $0.level < $1.level }) else { return nil }
        let outside = awake.filter { !session.contains($0.date) }
        let avg = inside.map(\.level).reduce(0, +) / Double(inside.count)
        let out = outside.isEmpty ? nil : outside.map(\.level).reduce(0, +) / Double(outside.count)
        return MarketStress(average: avg, peak: peak, outsideAverage: out)
    }

    /// Energy 0–100 through the day, Body Battery style: starts from Recovery at wake, drains with stress and exercise,
    /// recharges a little while you're calm. A heuristic built from your heart rate.
    static func energy(_ d: DayScores, schedule: EnergySchedule, until end: Date) -> [LevelPoint] {
        var level = 30 + 0.65 * (d.recovery ?? 55)
        var out: [LevelPoint] = [LevelPoint(date: schedule.wake, level: level)]
        let buckets = Dictionary(d.stress.map { ($0.date, $0.level) }, uniquingKeysWith: { a, _ in a })
        var t = schedule.wake
        let step = 15.0 * 60
        while t < end {
            let bucket = Date(timeIntervalSinceReferenceDate: floor(t.timeIntervalSinceReferenceDate / 900) * 900)
            if d.raw.workouts.contains(where: { $0.start <= t && t <= $0.end }) {
                level -= 1.8
            } else if let s = buckets[bucket] {
                level -= s < 0.4 ? -0.3 : 0.2 + 0.55 * s
            } else {
                level -= 0.45   // no reading: assume ordinary waking drain
            }
            level = level.clamped(3, 100)
            t = t.addingTimeInterval(step)
            out.append(LevelPoint(date: t, level: level))
        }
        return out
    }
}
