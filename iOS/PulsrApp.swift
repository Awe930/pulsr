import SwiftUI
import AppIntents

@main
struct PulsrApp: App {
    @State private var store = MetricsStore()
    @State private var journal = JournalStore()
    @State private var coach = Coach()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(journal)
                .environment(coach)
                .preferredColorScheme((Appearance(rawValue: appearance) ?? .system).colorScheme)
                .task { if store.hasOnboarded { await store.load() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.hasOnboarded { Task { await store.load() } }
                }
        }
    }
}

/// Light, dark, or follow the phone. Stored on its own so profile data is never reset by a new setting.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "nine30.appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Match phone"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Route: Hashable {
    case recovery, sleep, strain, stress, bodyAge, healthMonitor, journalInsights, focus
}

struct RootView: View {
    @Environment(MetricsStore.self) private var store

    var body: some View {
        if store.hasOnboarded {
            TabView {
                Tab("Today", systemImage: "circle.circle") { NavigationStack { TodayView().routes() } }
                Tab("Trends", systemImage: "chart.xyaxis.line") { NavigationStack { TrendsView().routes() } }
                Tab("Journal", systemImage: "book.closed") { NavigationStack { JournalView().routes() } }
                Tab("Coach", systemImage: "sparkles") { NavigationStack { CoachView() } }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tint(.primary)
        } else {
            OnboardingView()
        }
    }
}

extension View {
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .recovery: RecoveryDetailView()
            case .sleep: SleepDetailView()
            case .strain: StrainDetailView()
            case .stress: StressView()
            case .bodyAge: BodyAgeView()
            case .healthMonitor: HealthMonitorView()
            case .journalInsights: JournalInsightsView()
            case .focus: FocusView()
            }
        }
    }
}

// MARK: - Siri and Shortcuts (Nine30)

private func todayLine(_ pick: (TodaySummary) -> String) -> String {
    guard let s = TodaySummary.load() else { return "Open Nine30 once to load your scores." }
    guard s.day == DayLogStore.dayKey(.now) else { return "Open Nine30 once today to refresh your scores." }
    return pick(s)
}

struct RecoveryIntent: AppIntent {
    static let title: LocalizedStringResource = "Recovery today"
    static let description = IntentDescription("Today's Nine30 Recovery and strain target.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: todayLine { $0.recoveryLine }))
    }
}

struct FocusWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "Focus window today"
    static let description = IntentDescription("Today's predicted peak focus and afternoon dip.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: todayLine { $0.focusLine }))
    }
}

struct Nine30Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecoveryIntent(),
                    phrases: ["What's my recovery in \(.applicationName)", "\(.applicationName) recovery"],
                    shortTitle: "Recovery", systemImageName: "circle.circle")
        AppShortcut(intent: FocusWindowIntent(),
                    phrases: ["When is my focus window in \(.applicationName)", "\(.applicationName) focus window"],
                    shortTitle: "Focus window", systemImageName: "sun.max")
    }
}
