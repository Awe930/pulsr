import Foundation
import HealthKit

protocol HealthDataSource {
    func requestAuthorization() async throws
    /// Returns `count` days ending today, oldest first. Only the last `detailedDays` include minute heart rate.
    func loadDays(count: Int, detailedDays: Int) async throws -> [RawDay]
    func profileHints() -> (age: Int?, sex: Sex?)
    /// RMSSD from the most recent beat-to-beat series (a Breathe session on the watch) since `since`.
    func latestMorningRMSSD(since: Date) async throws -> (rmssd: Double, beats: Int)?
}

/// Collects beats from a heartbeat series query, which calls back once per beat.
private final class BeatCollector {
    var times: [Double?] = []
    var finished = false
}

/// Reads everything your Apple Watch writes to Apple Health. Nothing is ever written back.
final class HealthKitSource: HealthDataSource {
    private let store = HKHealthStore()
    private let cal = Calendar.current

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        let quantities: [HKQuantityTypeIdentifier] = [
            .heartRate, .heartRateVariabilitySDNN, .restingHeartRate, .respiratoryRate,
            .oxygenSaturation, .appleSleepingWristTemperature, .vo2Max, .stepCount, .activeEnergyBurned,
        ]
        var set = Set<HKObjectType>(quantities.map { HKQuantityType($0) })
        set.insert(HKCategoryType(.sleepAnalysis))
        set.insert(HKObjectType.workoutType())
        set.insert(HKSeriesType.heartbeat())   // beat-to-beat data for the morning HRV check-in
        set.insert(HKCharacteristicType(.dateOfBirth))
        set.insert(HKCharacteristicType(.biologicalSex))
        return set
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func latestMorningRMSSD(since: Date) async throws -> (rmssd: Double, beats: Int)? {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: .now, options: [])
        let samples: [HKSample] = try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: HKSeriesType.heartbeat(), predicate: predicate, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, results, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: results ?? []) }
            }
            store.execute(query)
        }
        guard let series = samples.first as? HKHeartbeatSeriesSample else { return nil }
        let collector = BeatCollector()
        let times: [Double?] = try await withCheckedThrowingContinuation { cont in
            let query = HKHeartbeatSeriesQuery(heartbeatSeries: series) { _, timeSinceStart, precededByGap, done, error in
                guard !collector.finished else { return }
                if let error {
                    collector.finished = true
                    cont.resume(throwing: error)
                    return
                }
                if precededByGap { collector.times.append(nil) }
                collector.times.append(timeSinceStart)
                if done {
                    collector.finished = true
                    cont.resume(returning: collector.times)
                }
            }
            store.execute(query)
        }
        return ScoreEngine.rmssd(beatTimes: times)
    }

    func profileHints() -> (age: Int?, sex: Sex?) {
        var age: Int?
        if let dob = try? store.dateOfBirthComponents(), let birth = cal.date(from: dob) {
            age = cal.dateComponents([.year], from: birth, to: .now).year
        }
        var sex: Sex?
        switch (try? store.biologicalSex())?.biologicalSex {
        case .female: sex = .female
        case .male: sex = .male
        case .other: sex = .other
        default: sex = nil
        }
        return (age, sex)
    }

    func loadDays(count: Int, detailedDays: Int) async throws -> [RawDay] {
        let today = cal.startOfDay(for: .now)
        let first = cal.date(byAdding: .day, value: -(count - 1), to: today)!
        let end = cal.date(byAdding: .day, value: 1, to: today)!
        let rangeStart = first.addingTimeInterval(-9 * 3600)   // previous evening, for the first night

        async let sleepSamples = categorySamples(.sleepAnalysis, from: rangeStart, to: end)
        async let hrv = quantitySamples(.heartRateVariabilitySDNN, from: rangeStart, to: end, unit: .secondUnit(with: .milli))
        async let rhr = quantitySamples(.restingHeartRate, from: first, to: end, unit: .bpm)
        async let resp = quantitySamples(.respiratoryRate, from: rangeStart, to: end, unit: .bpm)
        async let temp = quantitySamples(.appleSleepingWristTemperature, from: rangeStart, to: end, unit: .degreeCelsius())
        async let spo2 = quantitySamples(.oxygenSaturation, from: rangeStart, to: end, unit: .percent())
        async let vo2 = quantitySamples(.vo2Max, from: cal.date(byAdding: .day, value: -180, to: today)!, to: end, unit: HKUnit(from: "ml/kg*min"))
        async let steps = dailySums(.stepCount, from: first, to: end, unit: .count())
        async let energy = dailySums(.activeEnergyBurned, from: first, to: end, unit: .kilocalorie())
        async let workouts = workoutSamples(from: first, to: end)
        let detailStart = cal.date(byAdding: .day, value: -(detailedDays - 1), to: today)!
        async let heartRate = minuteHeartRate(from: detailStart, to: end)

        let nights = groupSleep(try await sleepSamples)
        let hrvAll = try await hrv, respAll = try await resp, tempAll = try await temp, spo2All = try await spo2
        let rhrAll = try await rhr, vo2All = try await vo2
        let stepsByDay = try await steps, energyByDay = try await energy
        let workoutList = try await workouts, hrAll = try await heartRate

        var days: [RawDay] = []
        for offset in 0..<count {
            let day = cal.date(byAdding: .day, value: offset, to: first)!
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            var raw = RawDay(date: day)
            raw.sleep = nights[day]

            // Nightly metrics: samples recorded during the sleep window (or 00:00–08:00 without sleep data).
            let window: ClosedRange<Date> = raw.sleep.map { $0.start...$0.end } ?? day...day.addingTimeInterval(8 * 3600)
            // Median, not mean: one noisy reading should not move the whole night.
            let nightHRV = hrvAll.filter { window.contains($0.date) }.map(\.value)
            raw.hrv = median(nightHRV)
            raw.hrvSampleCount = nightHRV.count
            raw.respiratoryRate = mean(respAll.filter { window.contains($0.date) }.map(\.value))
            raw.spo2 = mean(spo2All.filter { window.contains($0.date) }.map(\.value))
            raw.wristTemperature = tempAll.last { $0.date >= day.addingTimeInterval(-9 * 3600) && $0.date < next }?.value
            raw.restingHR = rhrAll.last { $0.date >= day && $0.date < next }?.value
            raw.vo2Max = vo2All.last { $0.date < next }?.value
            raw.steps = stepsByDay[day] ?? 0
            raw.activeEnergy = energyByDay[day] ?? 0
            raw.workouts = workoutList.filter { $0.start >= day && $0.start < next }
            raw.heartRate = hrAll.filter { $0.date >= day && $0.date < next }
            days.append(raw)
        }
        return days
    }

    // MARK: Queries

    private struct Value { var date: Date; var value: Double }

    private func predicate(_ start: Date, _ end: Date) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    }

    private func quantitySamples(_ id: HKQuantityTypeIdentifier, from start: Date, to end: Date, unit: HKUnit) async throws -> [Value] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate(start, end))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).map { Value(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    private func categorySamples(_ id: HKCategoryTypeIdentifier, from start: Date, to end: Date) async throws -> [HKCategorySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(id), predicate: predicate(start, end))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }

    private func dailySums(_ id: HKQuantityTypeIdentifier, from start: Date, to end: Date, unit: HKUnit) async throws -> [Date: Double] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate(start, end)),
            options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
        let collection = try await descriptor.result(for: store)
        var out: [Date: Double] = [:]
        for s in collection.statistics() {
            out[cal.startOfDay(for: s.startDate)] = s.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
        return out
    }

    private func minuteHeartRate(from start: Date, to end: Date) async throws -> [HeartRatePoint] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate), predicate: predicate(start, end)),
            options: .discreteAverage, anchorDate: start, intervalComponents: DateComponents(minute: 1))
        let collection = try await descriptor.result(for: store)
        return collection.statistics().compactMap { s in
            s.averageQuantity().map { HeartRatePoint(date: s.startDate, bpm: $0.doubleValue(for: .bpm)) }
        }
    }

    private func workoutSamples(from start: Date, to end: Date) async throws -> [WorkoutSummary] {
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate(start, end))], sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).map { w in
            let info = Self.describe(w.workoutActivityType)
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            return WorkoutSummary(name: info.name, symbol: info.symbol, start: w.startDate, end: w.endDate, isStrength: info.strength, energyKcal: kcal)
        }
    }

    // MARK: Sleep grouping

    /// Groups sleep samples into nights keyed by the day you woke up. When several apps or devices
    /// recorded the same night, the source with the most staged data wins.
    private func groupSleep(_ samples: [HKCategorySample]) -> [Date: SleepSession] {
        var byNight: [Date: [String: [SleepSegment]]] = [:]
        for s in samples {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { continue }
            let stage: SleepStage
            switch value {
            case .inBed: continue
            case .awake: stage = .awake
            case .asleepREM: stage = .rem
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            default: stage = .asleep
            }
            let night = cal.startOfDay(for: s.startDate.addingTimeInterval(9 * 3600))
            let source = s.sourceRevision.source.bundleIdentifier
            byNight[night, default: [:]][source, default: []].append(SleepSegment(stage: stage, start: s.startDate, end: s.endDate))
        }
        return byNight.compactMapValues { sources in
            let best = sources.values.max { a, b in
                let sa = SleepSession(segments: a), sb = SleepSession(segments: b)
                return (sa.hasStages ? 1 : 0, sa.asleep) < (sb.hasStages ? 1 : 0, sb.asleep)
            }
            guard let best, !best.isEmpty else { return nil }
            let session = SleepSession(segments: best.sorted { $0.start < $1.start })
            return session.asleep > 2 * 3600 ? session : nil   // ignore naps
        }
    }

    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted(), mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }

    static func describe(_ type: HKWorkoutActivityType) -> (name: String, symbol: String, strength: Bool) {
        switch type {
        case .running: ("Running", "figure.run", false)
        case .walking: ("Walking", "figure.walk", false)
        case .cycling: ("Cycling", "figure.outdoor.cycle", false)
        case .swimming: ("Swimming", "figure.pool.swim", false)
        case .hiking: ("Hiking", "figure.hiking", false)
        case .yoga: ("Yoga", "figure.yoga", false)
        case .rowing: ("Rowing", "figure.rower", false)
        case .elliptical: ("Elliptical", "figure.elliptical", false)
        case .highIntensityIntervalTraining: ("HIIT", "figure.highintensity.intervaltraining", false)
        case .traditionalStrengthTraining: ("Strength", "figure.strengthtraining.traditional", true)
        case .functionalStrengthTraining: ("Functional", "figure.strengthtraining.functional", true)
        case .coreTraining: ("Core", "figure.core.training", true)
        case .crossTraining: ("Cross Training", "figure.cross.training", true)
        case .soccer: ("Football", "figure.soccer", false)
        case .basketball: ("Basketball", "figure.basketball", false)
        case .tennis: ("Tennis", "figure.tennis", false)
        case .boxing: ("Boxing", "figure.boxing", false)
        case .martialArts: ("Martial Arts", "figure.martial.arts", false)
        case .dance, .socialDance, .cardioDance: ("Dance", "figure.dance", false)
        case .pilates: ("Pilates", "figure.pilates", false)
        case .stairClimbing, .stairs: ("Stairs", "figure.stairs", false)
        case .mindAndBody, .flexibility: ("Mobility", "figure.flexibility", false)
        default: ("Workout", "figure.mixed.cardio", false)
        }
    }
}

extension HKUnit {
    static let bpm = HKUnit.count().unitDivided(by: .minute())
}
