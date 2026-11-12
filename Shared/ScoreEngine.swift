import Foundation

/// All scoring lives here, as plain functions over `RawDay` values.
/// The formulas are documented in docs/ALGORITHMS.md — keep the two in sync.
enum ScoreEngine {
    static let baselineWindow = 30
    static let calibrationNights = 7

    // MARK: Pipeline

    /// `days` must be sorted oldest → newest. Each day is scored against the days before it.
    static func score(_ input: [RawDay], profile: UserProfile, logs: [String: DayLog] = [:]) -> [DayScores] {
        // Morning readings from check-ins join the raw data; sick and travel days are kept out of every baseline.
        let days: [RawDay] = input.map { d in
            var d = d
            d.morningRMSSD = logs[DayLogStore.dayKey(d.date)]?.morningRMSSD
            return d
        }
        let excluded: [Bool] = days.map { logs[DayLogStore.dayKey($0.date)]?.status?.excludedFromBaseline ?? false }
        var result: [DayScores] = []
        for (i, raw) in days.enumerated() {
            let history = (max(0, i - baselineWindow)..<i).filter { !excluded[$0] }.map { days[$0] }
            var s = DayScores(raw: raw)
            let dayLog = logs[DayLogStore.dayKey(raw.date)]
            s.status = dayLog?.status ?? .normal
            s.readiness = dayLog?.readiness

            s.hrvBaseline = baseline(history.compactMap(\.hrv).map { log($0) }, prior: Baseline(mean: log(45), sd: 0.30, samples: 0))
            s.rhrBaseline = baseline(history.compactMap(\.restingHR), prior: Baseline(mean: 60, sd: 5, samples: 0))
            s.respBaseline = baseline(history.compactMap(\.respiratoryRate), prior: Baseline(mean: 15, sd: 1, samples: 0))
            s.tempBaseline = baseline(history.compactMap(\.wristTemperature), prior: nil)
            s.rmssdBaseline = baseline(history.compactMap(\.morningRMSSD).map { log($0) }, prior: Baseline(mean: log(42), sd: 0.35, samples: 0))
            s.isCalibrating = history.compactMap(\.hrv).count < calibrationNights

            // 7-day HRV trend against your range (Plews-style: the trend carries the verdict, one night does not).
            let lastWeek = days[max(0, i - 6)...i].compactMap(\.hrv).map { log($0) }
            if lastWeek.count >= 3, let base = s.hrvBaseline {
                let trend = lastWeek.reduce(0, +) / Double(lastWeek.count)
                let swc = 0.5 * base.sd
                s.hrvTrend = exp(trend)
                s.hrvRange = exp(base.mean - swc)...exp(base.mean + swc)
                s.hrvStatus = trend < base.mean - swc ? .below : trend > base.mean + swc ? .above : .typical
            }

            let strainResult = strain(heartRate: raw.heartRate, restingHR: raw.restingHR ?? s.rhrBaseline?.mean ?? 60, profile: profile, workouts: raw.workouts)
            s.strain = strainResult.strain
            s.trimp = strainResult.trimp
            s.zoneMinutes = strainResult.zoneMinutes
            s.workoutStrain = strainResult.perWorkout
            s.strengthMinutes = raw.workouts.filter(\.isStrength).map(\.duration).reduce(0, +) / 60

            let previous = result.last
            s.sleepNeed = sleepNeed(profile: profile, previousStrain: previous?.strain, debt: previous?.sleepDebt ?? 0)
            s.sleepBalance = sleepBalance(days[max(0, i - 13)...i].map(\.sleep), goalHours: profile.sleepGoalHours)
            if let sleep = raw.sleep {
                let priorSleeps = history.suffix(4).compactMap(\.sleep)
                s.hoursVsNeeded = min(1, sleep.asleep / s.sleepNeed)
                s.sleepEfficiency = sleep.inBed > 0 ? sleep.asleep / sleep.inBed : nil
                s.sleepConsistency = consistency(sleep, previous: priorSleeps)
                s.sleepPerformance = 100 * (0.6 * (s.hoursVsNeeded ?? 0)
                                            + 0.2 * (s.sleepConsistency ?? 0.7)
                                            + 0.2 * (s.sleepEfficiency ?? 0.85))
            }

            let rmssdNights = history.compactMap(\.morningRMSSD).count
            let hrv = hrvZ(raw: raw, method: profile.hrvMethod, hrvTrend: s.hrvTrend, hrvBase: s.hrvBaseline,
                           rmssdBase: s.rmssdBaseline, rmssdNights: rmssdNights)
            s.hrvSource = hrv?.source
            s.recovery = recovery(hrvZ: hrv?.z, raw: raw, rhrBase: s.rhrBaseline, respBase: s.respBaseline, sleepPerformance: s.sleepPerformance)
            let usedMorning = hrv?.source == .morningRMSSD
            let trust = confidence(raw: raw, usedMorning: usedMorning,
                                   hrvNights: usedMorning ? rmssdNights : history.compactMap(\.hrv).count,
                                   hasHRV: hrv != nil, hasTrend: s.hrvTrend != nil)
            s.confidence = trust.0
            s.confidenceDetail = trust.1
            s.stress = stress(heartRate: raw.heartRate, restingHR: raw.restingHR ?? s.rhrBaseline?.mean ?? 60,
                              maxHR: profile.maxHeartRate, sleep: raw.sleep, workouts: raw.workouts)
            result.append(s)
        }
        return result
    }

    // MARK: Baselines

    /// Mean / SD of recent values, shrunk toward a population prior while there are few samples.
    static func baseline(_ values: [Double], prior: Baseline?) -> Baseline? {
        let n = Double(values.count)
        guard n > 0 || prior != nil else { return nil }
        let k = 4.0  // prior weight, in "nights"
        let sampleMean = n > 0 ? values.reduce(0, +) / n : 0
        let sampleVar = n > 1 ? values.map { pow($0 - sampleMean, 2) }.reduce(0, +) / (n - 1) : 0
        guard let prior else {
            guard n >= 3 else { return nil }
            return Baseline(mean: sampleMean, sd: max(sqrt(sampleVar), 0.1), samples: values.count)
        }
        let mean = (n * sampleMean + k * prior.mean) / (n + k)
        let variance = ((n - 1).clamped(0, .infinity) * sampleVar + k * prior.sd * prior.sd) / (max(n - 1, 0) + k)
        return Baseline(mean: mean, sd: max(sqrt(variance), prior.sd * 0.35), samples: values.count)
    }

    // MARK: Recovery (0–100)

    /// The HRV part of Recovery as a z-score. Morning RMSSD is used when chosen, read today and backed by 7+ mornings;
    /// otherwise overnight SDNN, half last night and half the 7-day trend. Z-scores are unitless, so both share one formula.
    static func hrvZ(raw: RawDay, method: HRVMethod, hrvTrend: Double?, hrvBase: Baseline?,
                     rmssdBase: Baseline?, rmssdNights: Int) -> (z: Double, source: HRVMethod)? {
        if method == .morningRMSSD, let r = raw.morningRMSSD, let rb = rmssdBase, rmssdNights >= calibrationNights {
            return (rb.z(log(r)).clamped(-3, 3), .morningRMSSD)
        }
        guard let hrv = raw.hrv, let base = hrvBase else { return nil }
        var z = base.z(log(hrv)).clamped(-3, 3)
        if let hrvTrend { z = 0.5 * z + 0.5 * base.z(log(hrvTrend)).clamped(-3, 3) }
        return (z, .overnightSDNN)
    }

    static func recovery(hrvZ: Double?, raw: RawDay, rhrBase: Baseline?, respBase: Baseline?, sleepPerformance: Double?) -> Double? {
        guard let hrvZ else { return nil }
        var composite = 0.55 * hrvZ
        var weight = 0.55
        if let rhr = raw.restingHR, let rhrBase {
            composite += 0.25 * -rhrBase.z(rhr).clamped(-3, 3); weight += 0.25
        }
        if let resp = raw.respiratoryRate, let respBase {
            composite += 0.05 * -abs(respBase.z(resp)).clamped(0, 3); weight += 0.05
        }
        if let sleepPerformance {
            composite += 0.15 * ((sleepPerformance / 100 - 0.85) / 0.12).clamped(-3, 2); weight += 0.15
        }
        composite /= weight
        return (100 / (1 + exp(-(1.25 * composite + 0.35)))).clamped(1, 99)
    }

    /// How much the day's Recovery can be trusted: readings last night, length of baseline, and whether a 7-day trend exists.
    static func confidence(raw: RawDay, usedMorning: Bool, hrvNights: Int, hasHRV: Bool, hasTrend: Bool) -> (ScoreConfidence, String) {
        guard hasHRV else { return (.low, "No HRV recorded last night") }
        var points = 0
        if usedMorning {
            points += 2   // a 1-minute beat-to-beat reading at rest beats a few spot checks
        } else {
            points += raw.hrvSampleCount >= 5 ? 2 : raw.hrvSampleCount >= 3 ? 1 : 0
        }
        points += hrvNights >= 21 ? 2 : hrvNights >= calibrationNights ? 1 : 0
        points += hasTrend ? 1 : 0
        let level: ScoreConfidence = points >= 5 ? .high : points >= 3 ? .medium : .low
        let readings = usedMorning ? "morning reading" : raw.hrvSampleCount == 1 ? "1 reading" : "\(raw.hrvSampleCount) readings"
        return (level, "\(readings) · \(hrvNights) nights")
    }

    /// RMSSD in ms from beat times (seconds since series start; nil marks a gap in the series).
    /// Drops implausible intervals (outside 300–2000 ms) and jumps over 20% from the previous beat, which are usually artifacts.
    static func rmssd(beatTimes: [Double?]) -> (rmssd: Double, beats: Int)? {
        var intervals: [Double?] = []
        var last: Double?
        for t in beatTimes {
            guard let t else { last = nil; intervals.append(nil); continue }
            if let last {
                let rr = (t - last) * 1000
                intervals.append((300.0...2000.0).contains(rr) ? rr : nil)
            }
            last = t
        }
        var diffs: [Double] = []
        var prev: Double?
        for rr in intervals {
            guard let rr else { prev = nil; continue }
            if let p = prev {
                if abs(rr - p) / p <= 0.2 { diffs.append(rr - p); prev = rr }
            } else {
                prev = rr
            }
        }
        guard diffs.count >= 30 else { return nil }
        let value = (diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count)).squareRoot()
        return (value, diffs.count + 1)
    }

    // MARK: Strain (0–21)

    struct StrainResult {
        var strain: Double
        var trimp: Double = 0
        var zoneMinutes: [Double]
        var perWorkout: [UUID: Double]
    }

    /// Banister TRIMP accumulated per minute, mapped onto a 0–21 logarithmic scale.
    static func strain(heartRate: [HeartRatePoint], restingHR: Double, profile: UserProfile, workouts: [WorkoutSummary]) -> StrainResult {
        let minutes = fillGaps(heartRate)
        let maxHR = profile.maxHeartRate
        let (a, b) = profile.sex == .female ? (0.86, 1.67) : (0.64, 1.92)
        var trimp = 0.0
        var zones = Array(repeating: 0.0, count: 6)
        var perWorkoutTrimp: [UUID: Double] = [:]

        for p in minutes {
            let zone = zoneIndex(bpm: p.bpm, maxHR: maxHR)
            zones[zone] += 1
            let hrr = ((p.bpm - restingHR) / (maxHR - restingHR)).clamped(0, 1)
            guard hrr >= 0.25 else { continue }   // sitting and light movement count as rest
            let load = hrr * a * exp(b * hrr)
            trimp += load
            if let w = workouts.first(where: { $0.start <= p.date && p.date <= $0.end }) {
                perWorkoutTrimp[w.id, default: 0] += load
            }
        }
        // Lifting keeps heart rate low but still loads the body. Heuristic: each strength minute adds a fixed TRIMP,
        // only on days with heart-rate data so older days stay comparable.
        if !heartRate.isEmpty {
            for w in workouts where w.isStrength {
                let bonus = w.duration / 60 * strengthTrimpPerMinute
                trimp += bonus
                perWorkoutTrimp[w.id, default: 0] += bonus
            }
        }
        return StrainResult(strain: strainScale(trimp), trimp: trimp, zoneMinutes: zones, perWorkout: perWorkoutTrimp.mapValues(strainScale))
    }

    static func strainScale(_ trimp: Double) -> Double { 21 * (1 - exp(-trimp / 125)) }

    // MARK: Training balance (Nine30)

    struct LoadPoint: Identifiable {
        var id: Date { date }
        var date: Date
        var fitness: Double
        var fatigue: Double
    }

    struct TrainingBalance {
        var fitness: Double        // 42-day weighted load (TRIMP/day)
        var fatigue: Double        // 7-day weighted load
        var form: Double           // fitness − fatigue
        var formLabel: String
        var acwr: Double?          // last 7 days ÷ last 28 days
        var acwrLabel: String?
        var series: [LoadPoint]
    }

    /// Banister-style fitness/fatigue from daily TRIMP, over days that have heart-rate data. Needs 3+ weeks.
    static func trainingBalance(_ days: [DayScores]) -> TrainingBalance? {
        guard let first = days.firstIndex(where: { !$0.raw.heartRate.isEmpty }) else { return nil }
        let span = Array(days[first...])
        guard span.count >= 21 else { return nil }
        let loads = span.map { $0.raw.heartRate.isEmpty ? 0 : $0.trimp }
        let kFit = 1 - exp(-1.0 / 42), kFat = 1 - exp(-1.0 / 7)
        var fit = loads.prefix(7).reduce(0, +) / 7
        var fat = fit
        var series: [LoadPoint] = []
        for (d, load) in zip(span, loads) {
            fit += kFit * (load - fit)
            fat += kFat * (load - fat)
            series.append(LoadPoint(date: d.date, fitness: fit, fatigue: fat))
        }
        let form = fit - fat
        let rel = fit > 0 ? form / fit : 0
        let formLabel = rel > 0.1 ? "Fresh" : rel > -0.1 ? "Steady" : rel > -0.3 ? "Productive" : "Overreaching"
        var acwr: Double?
        if loads.count >= 28 {
            let acute = loads.suffix(7).reduce(0, +) / 7
            let chronic = loads.suffix(28).reduce(0, +) / 28
            if chronic > 0 { acwr = acute / chronic }
        }
        let acwrLabel = acwr.map { r -> String in
            r < 0.8 ? "Below your usual load" : r <= 1.3 ? "Sweet spot" : r <= 1.5 ? "Ramping fast" : "Spike: injury risk up"
        }
        return TrainingBalance(fitness: fit, fatigue: fat, form: form, formLabel: formLabel, acwr: acwr, acwrLabel: acwrLabel, series: series)
    }

    // MARK: Resilience and plan streak (Nine30)

    struct Resilience {
        var score: Double          // 0...100
        var level: String
        var recoveryPart: Double   // average Recovery over 14 days
        var calmPart: Double       // 100 = no time in high stress while awake
        var sleepPart: Double      // 100 = no sleep debt
        var change: Double?        // vs. the 14 days before
    }

    // MARK: Week in review

    struct WeekReview {
        var days: [DayScores]
        var recovery: Double?, priorRecovery: Double?
        var sleep: TimeInterval?, priorSleep: TimeInterval?
        var strain: Double?, priorStrain: Double?
        var hrv: Double?, priorHRV: Double?
        var followed: Int, counted: Int
        var best: DayScores?, toughest: DayScores?
        var sleepBalance: TimeInterval?
    }

    /// The last 7 days against the 7 before. Strain and the plan count finished days only; today is still open.
    static func weekReview(_ all: [DayScores]) -> WeekReview? {
        guard all.count >= 3 else { return nil }
        let week = Array(all.suffix(7))
        let prior = Array(all.dropLast(7).suffix(7))
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        func avgRecovery(_ d: [DayScores]) -> Double? { avg(d.compactMap(\.recovery)) }
        func avgSleep(_ d: [DayScores]) -> Double? { avg(d.compactMap { $0.raw.sleep?.asleep }) }
        func avgStrain(_ d: [DayScores]) -> Double? { avg(d.dropLast().filter { !$0.raw.heartRate.isEmpty }.map(\.strain)) }
        func avgHRV(_ d: [DayScores]) -> Double? { avg(d.compactMap(\.raw.hrv)) }
        let finished = week.dropLast().filter { !$0.raw.heartRate.isEmpty }
        let followed = finished.filter { d in
            let t = strainTarget(for: d)
            return d.strain >= t.lowerBound - 1 && d.strain <= t.upperBound + 1
        }.count
        let scored = week.filter { $0.recovery != nil }
        return WeekReview(days: week,
                          recovery: avgRecovery(week), priorRecovery: avgRecovery(prior),
                          sleep: avgSleep(week), priorSleep: avgSleep(prior),
                          strain: avgStrain(week), priorStrain: prior.isEmpty ? nil : avg(prior.filter { !$0.raw.heartRate.isEmpty }.map(\.strain)),
                          hrv: avgHRV(week), priorHRV: avgHRV(prior),
                          followed: followed, counted: finished.count,
                          best: scored.max { ($0.recovery ?? 0) < ($1.recovery ?? 0) },
                          toughest: scored.min { ($0.recovery ?? 0) < ($1.recovery ?? 0) },
                          sleepBalance: week.last?.sleepBalance)
    }

    // MARK: Recovery vs how you felt

    struct FeltPair: Identifiable {
        var id: Date { date }
        var date: Date
        var felt: Int
        var recovery: Double
    }

    struct FeltAgreement {
        var pairs: [FeltPair]
        var r: Double?                 // Pearson correlation, once there are enough mornings
        var averages: [Int: Double]    // mean Recovery per rating
        static let minimum = 7
    }

    /// Pairs each morning's 1–5 rating with that day's Recovery score.
    static func feltAgreement(_ days: [DayScores], logs: [String: DayLog]) -> FeltAgreement {
        let pairs = days.compactMap { d -> FeltPair? in
            guard let r = d.recovery, let felt = logs[DayLogStore.dayKey(d.date)]?.readiness else { return nil }
            return FeltPair(date: d.date, felt: felt, recovery: r)
        }
        var sums: [Int: (Double, Int)] = [:]
        for p in pairs { let s = sums[p.felt] ?? (0, 0); sums[p.felt] = (s.0 + p.recovery, s.1 + 1) }
        let averages = sums.mapValues { $0.0 / Double($0.1) }
        var r: Double?
        if pairs.count >= FeltAgreement.minimum {
            let n = Double(pairs.count)
            let mx = pairs.map { Double($0.felt) }.reduce(0, +) / n
            let my = pairs.map(\.recovery).reduce(0, +) / n
            var sxx = 0.0, syy = 0.0, sxy = 0.0
            for p in pairs {
                let dx = Double(p.felt) - mx, dy = p.recovery - my
                sxx += dx * dx; syy += dy * dy; sxy += dx * dy
            }
            if sxx > 0, syy > 0 { r = sxy / (sxx * syy).squareRoot() }
        }
        return FeltAgreement(pairs: pairs, r: r, averages: averages)
    }

    /// Oura-style 14-day balance of strain on the system and recovery from it. Needs 10+ days with Recovery.
    static func resilience(_ days: [DayScores]) -> Resilience? {
        func compute(_ window: [DayScores]) -> (score: Double, rec: Double, calm: Double, sleep: Double)? {
            let recs = window.compactMap(\.recovery)
            guard recs.count >= 10 else { return nil }
            let rec = recs.reduce(0, +) / Double(recs.count)
            var high = 0, total = 0
            for d in window {
                for p in d.stress where !(d.raw.sleep.map { $0.start <= p.date && p.date <= $0.end } ?? false) {
                    total += 1
                    if p.level >= 2 { high += 1 }
                }
            }
            let calm = total > 0 ? 100 * (1 - min(Double(high) / Double(total) * 2.5, 1)) : 70
            let balanceHours = (window.last?.sleepBalance ?? 0) / 3600
            let sleep = balanceHours >= 0 ? 100 : max(0, 100 + balanceHours * 25)
            return (0.5 * rec + 0.3 * calm + 0.2 * sleep, rec, calm, sleep)
        }
        guard let now = compute(Array(days.suffix(14))) else { return nil }
        let before = days.count >= 28 ? compute(Array(days.dropLast(14).suffix(14))) : nil
        let s = now.score
        let level = s >= 80 ? "Exceptional" : s >= 68 ? "Strong" : s >= 56 ? "Solid" : s >= 44 ? "Adequate" : "Limited"
        return Resilience(score: s, level: level, recoveryPart: now.rec, calmPart: now.calm, sleepPart: now.sleep,
                          change: before.map { s - $0.score })
    }

    struct PlanStreak {
        var current: Int
        var hits: Int
        var days: Int
        /// The last finished day, so a zero streak can say why.
        var lastStrain: Double? = nil
        var lastTarget: ClosedRange<Double>? = nil
    }

    /// A day counts when its strain landed inside that day's target (±1), rest days included. Today is still open, so it's left out.
    static func planStreak(_ days: [DayScores]) -> PlanStreak? {
        let done = Array(days.dropLast()).filter { !$0.raw.heartRate.isEmpty }
        guard !done.isEmpty else { return nil }
        let followed: (DayScores) -> Bool = { d in
            let t = strainTarget(for: d)
            return d.strain >= t.lowerBound - 1 && d.strain <= t.upperBound + 1
        }
        var current = 0
        for d in done.reversed() {
            if followed(d) { current += 1 } else { break }
        }
        let recent = Array(done.suffix(14))
        return PlanStreak(current: current, hits: recent.filter(followed).count, days: recent.count,
                          lastStrain: done.last?.strain, lastTarget: done.last.map { strainTarget(for: $0) })
    }

    /// TRIMP per minute of strength training (about a steady moderate effort). A judgment call, documented in ALGORITHMS.md.
    static let strengthTrimpPerMinute = 0.6

    /// 0 = below zone 1, 1…5 = zones by % of max heart rate (50/60/70/80/90).
    static func zoneIndex(bpm: Double, maxHR: Double) -> Int {
        let pct = bpm / maxHR
        switch pct {
        case ..<0.5: return 0
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }

    /// Apple Watch samples heart rate every few minutes outside workouts; interpolate gaps up to 10 minutes.
    static func fillGaps(_ points: [HeartRatePoint]) -> [HeartRatePoint] {
        guard points.count > 1 else { return points }
        var out: [HeartRatePoint] = []
        for (p, next) in zip(points, points.dropFirst()) {
            out.append(p)
            let gap = Int(next.date.timeIntervalSince(p.date) / 60)
            guard gap > 1, gap <= 10 else { continue }
            for m in 1..<gap {
                let t = Double(m) / Double(gap)
                out.append(HeartRatePoint(date: p.date.addingTimeInterval(Double(m) * 60), bpm: p.bpm + (next.bpm - p.bpm) * t))
            }
        }
        out.append(points[points.count - 1])
        return out
    }

    /// Strain range for a scored day: rest when marked sick, otherwise by recovery.
    static func strainTarget(for d: DayScores) -> ClosedRange<Double> {
        d.status == .sick ? 0...8 : strainTarget(recovery: d.recovery)
    }

    /// Strain range that best matches today's recovery.
    static func strainTarget(recovery: Double?) -> ClosedRange<Double> {
        guard let recovery else { return 10...14 }
        switch RecoveryZone(recovery) {
        case .green: return 14...18
        case .yellow: return 10...14
        case .red: return 4...10
        }
    }

    // MARK: Sleep

    /// Tonight's need: your goal, plus extra after a hard day, plus a slice of your sleep debt (about a fifth a night, at most 1 h).
    static func sleepNeed(profile: UserProfile, previousStrain: Double?, debt: TimeInterval) -> TimeInterval {
        var hours = profile.sleepGoalHours
        if let previousStrain, previousStrain > 10 { hours += (previousStrain - 10) * 0.06 }
        hours += min(debt / 3600 * 0.2, 1.0)
        return hours * 3600
    }

    static let maxSleepSurplus: TimeInterval = 3 * 3600
    /// Extra sleep past your goal helps less than missing sleep hurts, so surplus nights count at half weight.
    /// A judgment call, to be checked against readiness ratings after 4–6 weeks.
    static let surplusWeight = 0.5

    /// Sleep balance over the last 14 nights (oldest first, last night last), measured against your goal so it cannot compound.
    /// Recent nights weigh more: last night counts fully, two weeks ago about 1/14.
    /// Above goal adds surplus, below goal adds debt. Surplus is capped: banked sleep helps, but not without limit.
    static func sleepBalance(_ nights: [SleepSession?], goalHours: Double) -> TimeInterval {
        let n = nights.count
        guard n > 0 else { return 0 }
        var balance = 0.0
        for (i, night) in nights.enumerated() {
            guard let slept = night?.asleep else { continue }   // a night without data neither adds nor repays
            let weight = Double(14 - (n - 1 - i)) / 14
            let delta = slept - goalHours * 3600
            balance += weight * (delta > 0 ? delta * surplusWeight : delta)
        }
        return min(balance, maxSleepSurplus)
    }

    /// 1 = went to bed and woke up at exactly the same times as the previous nights.
    static func consistency(_ sleep: SleepSession, previous: [SleepSession]) -> Double? {
        guard !previous.isEmpty else { return nil }
        func minuteOfDay(_ d: Date) -> Double {
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            if m < 12 * 60 { m += 24 * 60 }   // after-midnight bedtimes stay on the same axis
            return m
        }
        func wakeMinute(_ d: Date) -> Double {
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        let bedDev = previous.map { abs(minuteOfDay($0.start) - minuteOfDay(sleep.start)) }.reduce(0, +) / Double(previous.count)
        let wakeDev = previous.map { abs(wakeMinute($0.end) - wakeMinute(sleep.end)) }.reduce(0, +) / Double(previous.count)
        return (1 - (bedDev + wakeDev) / 2 / 120).clamped(0, 1)
    }

    /// Suggested bedtime for tonight so that sleep need is met before the usual wake-up time.
    static func recommendedBedtime(days: [DayScores], need: TimeInterval) -> Date? {
        let wakes = days.suffix(7).compactMap { $0.raw.sleep?.end }
        guard !wakes.isEmpty else { return nil }
        let cal = Calendar.current
        let avgMinute = wakes.map { Double(cal.component(.hour, from: $0) * 60 + cal.component(.minute, from: $0)) }.reduce(0, +) / Double(wakes.count)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!
        let wake = tomorrow.addingTimeInterval(avgMinute * 60)
        return wake.addingTimeInterval(-need / 0.92)   // allow for ~8 % time awake in bed
    }

    // MARK: Stress (0–3)

    static func stress(heartRate: [HeartRatePoint], restingHR: Double, maxHR: Double, sleep: SleepSession?, workouts: [WorkoutSummary]) -> [StressPoint] {
        guard !heartRate.isEmpty else { return [] }
        let span = 0.35 * (maxHR - restingHR)
        var buckets: [Date: [Double]] = [:]
        for p in heartRate {
            let level: Double
            if let sleep, sleep.start <= p.date, p.date <= sleep.end {
                level = (0.6 * (p.bpm - restingHR) / span).clamped(0, 1)
            } else if workouts.contains(where: { $0.start <= p.date && p.date <= $0.end }) {
                continue   // exertion is strain, not stress
            } else {
                level = 3 * ((p.bpm - restingHR - 5) / span).clamped(0, 1)
            }
            let bucket = Date(timeIntervalSinceReferenceDate: floor(p.date.timeIntervalSinceReferenceDate / 900) * 900)
            buckets[bucket, default: []].append(level)
        }
        return buckets.map { StressPoint(date: $0.key, level: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }

    // MARK: Body age

    static func bodyAge(days: [DayScores], profile: UserProfile) -> BodyAgeResult? {
        let recent = days.suffix(30)
        guard recent.count >= 7 else { return nil }
        let age = Double(profile.age)
        var factors: [BodyAgeFactor] = []

        if let vo2 = recent.compactMap(\.raw.vo2Max).last {
            let norm = (profile.sex == .female ? 43.0 : 50.0) - 0.32 * max(age - 20, 0)
            factors.append(.init(name: "VO₂ Max", value: String(format: "%.1f", vo2), years: (-(vo2 - norm) * 0.45).clamped(-6, 6)))
        }
        let rhrs = recent.compactMap(\.raw.restingHR)
        if !rhrs.isEmpty {
            let rhr = rhrs.reduce(0, +) / Double(rhrs.count)
            factors.append(.init(name: "Resting Heart Rate", value: "\(Int(rhr.rounded())) bpm", years: ((rhr - 62) * 0.15).clamped(-3, 4)))
        }
        let hrvs = recent.compactMap(\.raw.hrv)
        if !hrvs.isEmpty {
            let hrv = hrvs.reduce(0, +) / Double(hrvs.count)
            let norm = max(55 - 0.6 * (age - 20), 20)
            factors.append(.init(name: "Heart Rate Variability", value: "\(Int(hrv.rounded())) ms", years: (-(hrv - norm) * 0.06).clamped(-3, 3)))
        }
        let sleeps = recent.compactMap { $0.raw.sleep?.asleep }.map { $0 / 3600 }
        if !sleeps.isEmpty {
            let avg = sleeps.reduce(0, +) / Double(sleeps.count)
            factors.append(.init(name: "Sleep Duration", value: String(format: "%.1f h", avg), years: avg < 7 ? (7 - avg) * 1.2 : -0.5))
        }
        let consistency = recent.compactMap(\.sleepConsistency)
        if !consistency.isEmpty {
            let c = consistency.reduce(0, +) / Double(consistency.count)
            factors.append(.init(name: "Sleep Consistency", value: "\(Int(c * 100)) %", years: (0.8 - c) * 4))
        }
        let steps = recent.map(\.raw.steps)
        let avgSteps = steps.reduce(0, +) / Double(steps.count)
        factors.append(.init(name: "Daily Steps", value: avgSteps.formatted(.number.precision(.fractionLength(0))), years: (-(avgSteps - 7000) / 1000 * 0.25).clamped(-1.5, 2)))
        let zone2 = recent.map { $0.zoneMinutes[2...3].reduce(0, +) }.reduce(0, +) / Double(recent.count) * 7
        factors.append(.init(name: "Zone 2–3 per week", value: "\(Int(zone2)) min", years: (-(zone2 - 150) / 60 * 0.4).clamped(-2, 2)))

        let delta = factors.map(\.years).reduce(0, +).clamped(-12, 12)
        return BodyAgeResult(chronological: age, bodyAge: age + delta, factors: factors.sorted { $0.years < $1.years })
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
