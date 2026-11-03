import Foundation

// MARK: - Raw data (what a data source delivers, one value per day)

enum SleepStage: String, CaseIterable, Codable, Hashable {
    case awake, rem, core, deep, asleep

    var title: String {
        switch self {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .core: return "Light"
        case .deep: return "Deep"
        case .asleep: return "Asleep"
        }
    }

    /// Row in the hypnogram, top to bottom.
    var depth: Int {
        switch self {
        case .awake: return 0
        case .rem: return 1
        case .core, .asleep: return 2
        case .deep: return 3
        }
    }
}

struct SleepSegment: Hashable, Identifiable {
    var id: Date { start }
    var stage: SleepStage
    var start: Date
    var end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SleepSession: Hashable {
    var segments: [SleepSegment]

    var start: Date { segments.map(\.start).min() ?? .distantPast }
    var end: Date { segments.map(\.end).max() ?? .distantPast }
    var inBed: TimeInterval { end.timeIntervalSince(start) }
    var asleep: TimeInterval { segments.filter { $0.stage != .awake }.map(\.duration).reduce(0, +) }
    var hasStages: Bool { segments.contains { [.rem, .core, .deep].contains($0.stage) } }

    func duration(of stage: SleepStage) -> TimeInterval {
        segments.filter { $0.stage == stage }.map(\.duration).reduce(0, +)
    }

    /// Deep + REM share of total sleep.
    var restorativeShare: Double? {
        guard hasStages, asleep > 0 else { return nil }
        return (duration(of: .deep) + duration(of: .rem)) / asleep
    }
}

struct HeartRatePoint: Hashable {
    var date: Date
    var bpm: Double
}

struct WorkoutSummary: Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var start: Date
    var end: Date
    var isStrength: Bool
    var energyKcal: Double?
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct RawDay: Hashable {
    var date: Date                    // start of the calendar day
    var sleep: SleepSession?          // the night that ended on this day's morning
    var hrv: Double?                  // ms, median of the night's SDNN readings
    var hrvSampleCount = 0            // how many readings that median came from
    var morningRMSSD: Double?         // ms, from the morning check-in (1-minute Breathe session on the watch)
    var restingHR: Double?            // bpm
    var respiratoryRate: Double?      // breaths / min, during sleep
    var wristTemperature: Double?     // °C, absolute sleeping wrist temperature
    var spo2: Double?                 // 0...1
    var heartRate: [HeartRatePoint] = []  // ~1 per minute; only loaded for recent days
    var steps: Double = 0
    var activeEnergy: Double = 0      // kcal
    var workouts: [WorkoutSummary] = []
    var vo2Max: Double?               // ml/kg/min, latest known value
}

// MARK: - Computed scores

enum RecoveryZone {
    case red, yellow, green

    init(_ recovery: Double) {
        self = recovery >= 67 ? .green : recovery >= 34 ? .yellow : .red
    }
}

struct StressPoint: Hashable, Identifiable {
    var id: Date { date }
    var date: Date
    var level: Double   // 0...3
}

enum StressLevel: String {
    case low = "Low", medium = "Medium", high = "High"
    init(_ value: Double) { self = value < 1 ? .low : value < 2 ? .medium : .high }
}

/// How much data a day's Recovery rests on.
enum ScoreConfidence: Int, Comparable {
    case low = 1, medium = 2, high = 3

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .low: return "Low confidence"
        case .medium: return "Medium confidence"
        case .high: return "High confidence"
        }
    }
}

/// Where a vital sits against your own normal range.
enum VitalStatus {
    case below, typical, above

    var title: String {
        switch self {
        case .below: return "Below range"
        case .typical: return "Typical"
        case .above: return "Above range"
        }
    }
}

struct Baseline: Hashable {
    var mean: Double
    var sd: Double
    var samples: Int

    func z(_ value: Double) -> Double { (value - mean) / max(sd, 0.0001) }
}

struct DayScores: Hashable, Identifiable {
    var id: Date { raw.date }
    var raw: RawDay
    var date: Date { raw.date }

    // Recovery
    var recovery: Double?
    var hrvBaseline: Baseline?
    var rhrBaseline: Baseline?
    var respBaseline: Baseline?
    var tempBaseline: Baseline?
    var isCalibrating = true
    var confidence: ScoreConfidence = .low
    var status: DayStatus = .normal          // from the check-in; sick and travel days stay out of baselines
    var readiness: Int?                      // 1...5, how ready you felt
    var rmssdBaseline: Baseline?             // ln(morning RMSSD), from check-ins only
    var hrvSource: HRVMethod?                // which HRV fed today's Recovery
    var confidenceDetail = ""
    /// 7-day rolling HRV (geometric mean, ms) and where it sits against your range.
    var hrvTrend: Double?
    var hrvStatus: VitalStatus?
    /// Your normal HRV band in ms: baseline ± half a standard deviation (the smallest worthwhile change).
    var hrvRange: ClosedRange<Double>?

    // Sleep
    /// Sleep balance over the last 14 nights against your goal, recent nights weighted more.
    /// Positive = surplus (capped at +3 h), negative = debt.
    var sleepBalance: TimeInterval = 0
    var sleepDebt: TimeInterval { max(0, -sleepBalance) }
    /// Within ±30 min of balanced counts as on target (smaller swings are mostly watch noise).
    var sleepOnTarget: Bool { abs(sleepBalance) < 30 * 60 }
    var sleepPerformance: Double?
    var sleepNeed: TimeInterval = 8 * 3600
    var hoursVsNeeded: Double?
    var sleepConsistency: Double?
    var sleepEfficiency: Double?

    // Strain
    var strain: Double = 0
    var zoneMinutes: [Double] = Array(repeating: 0, count: 6)   // index 0 = below zone 1
    var strengthMinutes: Double = 0
    var workoutStrain: [UUID: Double] = [:]

    // Stress
    var stress: [StressPoint] = []
    var latestStress: Double? { stress.last?.level }
}

struct BodyAgeFactor: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var value: String
    var years: Double   // negative = younger
}

struct BodyAgeResult: Hashable {
    var chronological: Double
    var bodyAge: Double
    var factors: [BodyAgeFactor]
    var difference: Double { bodyAge - chronological }
}

// MARK: - Profile

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female, other
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct UserProfile: Codable, Hashable {
    var name: String = ""
    var age: Int = 30
    var sex: Sex = .male
    var sleepGoalHours: Double = 7.75
    var maxHeartRateOverride: Int?
    var hrvMethodRaw: String?   // optional so older saved profiles still load

    /// Morning RMSSD is the default; it falls back to overnight SDNN on days without a check-in or before 7 mornings exist.
    var hrvMethod: HRVMethod {
        get { hrvMethodRaw.flatMap(HRVMethod.init(rawValue:)) ?? .morningRMSSD }
        set { hrvMethodRaw = newValue.rawValue }
    }

    var maxHeartRate: Double {
        if let maxHeartRateOverride { return Double(maxHeartRateOverride) }
        return 208 - 0.7 * Double(age)   // Tanaka et al. 2001
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? "ME" : s.uppercased()
    }

    private static let key = "pulsr.profile"

    static func load() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else { return UserProfile() }
        return profile
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

// MARK: - Check-ins (Nine30)

/// Sick and travel days are skipped when Nine30 builds your normal ranges, so one rough day can't drag a baseline for a month.
enum DayStatus: String, Codable, CaseIterable, Identifiable {
    case normal, sick, travel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: return "Normal"
        case .sick: return "Sick"
        case .travel: return "Travel"
        }
    }
    var excludedFromBaseline: Bool { self != .normal }
}

enum HRVMethod: String, Codable, CaseIterable, Identifiable {
    case morningRMSSD, overnightSDNN
    var id: String { rawValue }
    var title: String {
        switch self {
        case .morningRMSSD: return "Morning check-in"
        case .overnightSDNN: return "Overnight (Apple)"
        }
    }
    var shortTitle: String {
        switch self {
        case .morningRMSSD: return "morning RMSSD"
        case .overnightSDNN: return "overnight SDNN"
        }
    }
}

/// What you tell Nine30 about a day.
struct DayLog: Codable, Hashable {
    var readiness: Int?          // 1...5
    var morningRMSSD: Double?    // ms
    var morningBeats: Int?
    var status: DayStatus?
    var checkedInAt: Date?
}

enum DayLogStore {
    private static let storageKey = "nine30.daylogs"

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func load() -> [String: DayLog] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let logs = try? JSONDecoder().decode([String: DayLog].self, from: data) else { return [:] }
        return logs
    }

    static func save(_ logs: [String: DayLog]) {
        if let data = try? JSONEncoder().encode(logs) { UserDefaults.standard.set(data, forKey: storageKey) }
    }
}
