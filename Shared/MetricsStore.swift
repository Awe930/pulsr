import Foundation
import Observation

@MainActor
@Observable
final class MetricsStore {
    enum Source: String { case health, demo }

    private(set) var days: [DayScores] = []
    private(set) var bodyAge: BodyAgeResult?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var selectedIndex = 0

    var profile: UserProfile {
        didSet { profile.save(); rescore() }
    }

    var source: Source {
        didSet {
            UserDefaults.standard.set(source.rawValue, forKey: "pulsr.source")
            Task { await load() }
        }
    }

    var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "pulsr.onboarded") }
    }

    private var rawDays: [RawDay] = []
    private let historyDays: Int
    private let detailedDays: Int

    init(historyDays: Int = 60, detailedDays: Int = 35) {
        self.historyDays = historyDays
        self.detailedDays = detailedDays
        profile = UserProfile.load()
        let defaultSource: Source = HealthKitSource.isAvailable ? .health : .demo
        source = Source(rawValue: UserDefaults.standard.string(forKey: "pulsr.source") ?? "") ?? defaultSource
        // `-demo` launch argument: screenshots and the Simulator, which has no Health data.
        if ProcessInfo.processInfo.arguments.contains("-demo") { source = .demo }
        hasOnboarded = UserDefaults.standard.bool(forKey: "pulsr.onboarded")
    }

    private var dataSource: HealthDataSource {
        source == .health && HealthKitSource.isAvailable ? HealthKitSource() : DemoSource()
    }

    var selected: DayScores? { days.indices.contains(selectedIndex) ? days[selectedIndex] : nil }
    var today: DayScores? { days.last }
    var isToday: Bool { selectedIndex == days.count - 1 }

    /// Days before the selected one, newest last (used for trends relative to the selection).
    func window(_ count: Int) -> [DayScores] {
        guard !days.isEmpty else { return [] }
        let end = min(selectedIndex, days.count - 1)
        return Array(days[max(0, end - count + 1)...end])
    }

    func connect() async {
        do {
            try await dataSource.requestAuthorization()
            let hints = dataSource.profileHints()
            if let age = hints.age { profile.age = age }
            if let sex = hints.sex { profile.sex = sex }
        } catch {
            errorMessage = error.localizedDescription
        }
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rawDays = try await dataSource.loadDays(count: historyDays, detailedDays: detailedDays)
            errorMessage = nil
            rescore()
            selectedIndex = max(days.count - 1, 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rescore() {
        guard !rawDays.isEmpty else { return }
        days = ScoreEngine.score(rawDays, profile: profile)
        bodyAge = ScoreEngine.bodyAge(days: days, profile: profile)
        selectedIndex = min(selectedIndex, max(days.count - 1, 0))
    }

    func step(_ delta: Int) {
        selectedIndex = (selectedIndex + delta).clamped(0, max(days.count - 1, 0))
    }
}
