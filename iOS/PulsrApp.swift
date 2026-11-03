import SwiftUI

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
    case recovery, sleep, strain, stress, bodyAge, healthMonitor, journalInsights
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
            }
        }
    }
}
