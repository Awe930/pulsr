import Foundation

/// Plain-language explanations generated from the scores. Shared by the phone and the watch.
enum Insights {
    static func hrvBaselineValue(_ d: DayScores) -> Double? { d.hrvBaseline.map { exp($0.mean) } }

    static func hrvChange(_ d: DayScores) -> Double? {
        guard let hrv = d.raw.hrv, let base = hrvBaselineValue(d) else { return nil }
        return (hrv - base) / base
    }

    static func headline(_ d: DayScores) -> (title: String, body: String) {
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
        let calibrating = d.isCalibrating ? " Nine30 is still learning your baseline, so expect scores to settle over the first week." : ""
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
