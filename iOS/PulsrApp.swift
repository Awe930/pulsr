import SwiftUI
import AppIntents
import UserNotifications

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
                .task {
                    if store.hasOnboarded {
                        await store.load()
                        await Nudges.refresh(store)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.hasOnboarded {
                        Task {
                            await store.load()
                            await Nudges.refresh(store)
                        }
                    }
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
    @AppStorage("nine30.tab") private var tab = 0

    var body: some View {
        if store.hasOnboarded {
            TabView(selection: $tab) {
                Tab("Today", systemImage: "circle.circle", value: 0) { NavigationStack { TodayView().routes() } }
                Tab("Trends", systemImage: "chart.xyaxis.line", value: 1) { NavigationStack { TrendsView().routes() } }
                Tab("Journal", systemImage: "book.closed", value: 2) { NavigationStack { JournalView().routes() } }
                Tab("Coach", systemImage: "sparkles", value: 3) { NavigationStack { CoachView() } }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .onAppear { tab = 0 }   // always open on Today
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

// MARK: - Reminders (Nine30)

/// Two local reminders, rescheduled every time the app opens: wind down 1 h before tonight's bedtime, and the
/// morning check-in 30 min after your usual wake time (skipped once today's check-in is done).
@MainActor
enum Nudges {
    static let windDownKey = "nine30.nudge.windDown"
    static let checkInKey = "nine30.nudge.checkIn"
    private static let ids = ["nine30.winddown", "nine30.checkin.today", "nine30.checkin.tomorrow",
                              "nine30.winddown.60", "nine30.winddown.15", "nine30.resign.1", "nine30.resign.2"]
        + (0..<3).flatMap { ["nine30.checkin.today.\($0)", "nine30.checkin.tomorrow.\($0)"] }

    static func refresh(_ store: MetricsStore) async {
        let defaults = UserDefaults.standard
        let windDownOn = defaults.object(forKey: windDownKey) as? Bool ?? true
        let checkInOn = defaults.object(forKey: checkInKey) as? Bool ?? true
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        // Re-sign: only the last two days, so it never nags.
        if let expiry = Signing.expiry {
            let resign = [("nine30.resign.1", expiry.addingTimeInterval(-24 * 3600), "Nine30 stops opening tomorrow. Plug your iPhone into the Mac and press ⌘R."),
                          ("nine30.resign.2", expiry.addingTimeInterval(-3 * 3600), "Nine30 stops opening in about 3 hours. Plug in and press ⌘R.")]
            for (id, date, body) in resign where date > .now {
                schedule(center, id: id, at: date, title: "Re-sign Nine30", body: body)
            }
        }

        guard windDownOn || checkInOn, let today = store.today else { return }
        let recent = Array(store.days.suffix(7))

        if windDownOn, let s = Focus.schedule(for: today, history: recent, profile: store.profile) {
            if s.windDown > .now {
                schedule(center, id: "nine30.winddown.60", at: s.windDown, title: "Wind down",
                         body: "Bedtime is \(s.bedtime.shortTime). Screens down, lights low.")
            }
            let last = s.bedtime.addingTimeInterval(-15 * 60)
            if last > .now {
                schedule(center, id: "nine30.winddown.15", at: last, title: "Bed in 15 minutes",
                         body: "Bedtime is \(s.bedtime.shortTime). Phone out of the bedroom.")
            }
        }
        if checkInOn, let wake = Focus.typicalWakeMinutes(recent) {
            let cal = Calendar.current
            let body = "One minute of Breathe on your watch, then rate how you feel."
            // Up to three reminders, 15 minutes apart. Checking in calls refresh(), which clears today's.
            for i in 0..<3 {
                let todayTime = cal.startOfDay(for: .now).addingTimeInterval((wake + 30 + Double(i) * 15) * 60)
                if store.dayLog(for: .now).checkedInAt == nil, todayTime > .now {
                    schedule(center, id: "nine30.checkin.today.\(i)", at: todayTime, title: "Morning check-in", body: body)
                }
                if let tomorrow = cal.date(byAdding: .day, value: 1, to: todayTime) {
                    schedule(center, id: "nine30.checkin.tomorrow.\(i)", at: tomorrow, title: "Morning check-in", body: body)
                }
            }
        }
    }

    private static func schedule(_ center: UNUserNotificationCenter, id: String, at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        center.add(request, withCompletionHandler: nil)
    }
}

/// Reads when the free Personal Team profile runs out (7 days after each ⌘R install).
enum Signing {
    static let expiry: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>"),
              start.lowerBound < end.upperBound,
              let plistData = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    /// Whole calendar days until expiry; nil when there is no profile (simulator, or demo builds).
    static var daysLeft: Int? {
        guard let expiry else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: expiry)).day
    }

    static var line: String? {
        guard let days = daysLeft, let expiry else { return nil }
        if expiry < .now { return "Signing expired · plug in and press ⌘R" }
        switch days {
        case ...0: return "Re-sign today by \(expiry.shortTime) · plug in and press ⌘R"
        case 1: return "Re-sign tomorrow"
        default: return "Re-sign in \(days) days"
        }
    }
}
