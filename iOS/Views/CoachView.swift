import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Answers questions about your data with Apple's on-device model (Apple Intelligence).
/// Falls back to simple rule-based answers on devices without it. Nothing is sent to a server.
@MainActor
@Observable
final class Coach {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        var fromUser: Bool
        var text: String
    }

    var messages: [Message] = []
    var isThinking = false
    private var lastContext = ""

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    private static let instructions = """
    You are Pulsr Coach, a concise, encouraging health and fitness coach inside an open-source Apple Watch app. \
    Recovery (0-100%) comes from overnight HRV, resting heart rate, respiratory rate and sleep. Strain (0-21) is cardiovascular load. \
    Answer in 2-5 short sentences using the user's numbers below. Be specific and practical. \
    You are not a doctor: for symptoms or medical questions, suggest seeing a professional. \
    Reply in the same language the user writes in.
    """

    var isOnDevice: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    func ask(_ question: String, context: String) async {
        messages.append(Message(fromUser: true, text: question))
        isThinking = true
        defer { isThinking = false }

        #if canImport(FoundationModels)
        if isOnDevice {
            if session == nil || context != lastContext {
                session = LanguageModelSession(instructions: Self.instructions + "\n\nUser data: " + context)
                lastContext = context
            }
            do {
                if let response = try await session?.respond(to: question) {
                    messages.append(Message(fromUser: false, text: response.content))
                    return
                }
            } catch {
                session = nil
            }
        }
        #endif
        messages.append(Message(fromUser: false, text: RuleCoach.answer(question, context: context)))
    }

    func reset() {
        messages = []
        #if canImport(FoundationModels)
        session = nil
        #endif
    }
}

/// Offline fallback: picks the most relevant canned guidance using the current numbers.
enum RuleCoach {
    static func answer(_ q: String, context: String) -> String {
        let s = q.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { s.contains($0) } }
        if has(["sleep", "сон", "спать", "bed"]) {
            return "Aim to be in bed early enough to hit tonight's sleep need — the Today screen shows a recommended bedtime. Keep bed and wake times within 30 minutes of each other, keep the room cool and dark, and stop caffeine 8+ hours before bed."
        }
        if has(["hrv", "variability", "вариабельн"]) {
            return "HRV rises with good sleep, low alcohol, steady aerobic training and managed stress. Compare it only to your own 30-day baseline — absolute values vary a lot between people. A few days below baseline usually means accumulated fatigue or illness coming on."
        }
        if has(["train", "workout", "strain", "run", "трен", "нагруз", "бег"]) {
            return "Match training to recovery: green days are for intervals or heavy sessions, yellow days for moderate zone 2 work, red days for walking, mobility or rest. Your strain target on the Today screen does this for you."
        }
        if has(["vo2", "cardio", "кардио"]) {
            return "VO₂ max improves fastest with 1–2 interval sessions per week (for example 4 × 4 minutes hard with 3 minutes easy) plus 2–3 hours of easy zone 2 cardio. Expect changes over 6–12 weeks."
        }
        if has(["stress", "стресс"]) {
            return "Stress here is estimated from heart rate above your resting baseline when you're not exercising. Short breathing breaks (6 breaths per minute for 5 minutes), walks and daylight help bring it down."
        }
        return "Here's where you stand: \(context.prefix(260))… Ask me about sleep, HRV, training or stress. (On iPhones with Apple Intelligence, answers are generated on-device and are more personal.)"
    }
}

struct CoachView: View {
    @Environment(MetricsStore.self) private var store
    @Environment(Coach.self) private var coach
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let suggestions = ["How can I improve my HRV?", "Should I train hard today?", "Why was my sleep score low?", "How do I lower my body age?"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 6) {
                        HaloOrb(palette: .spectral, energy: 1, speed: coach.isThinking ? 2.2 : 1.3)
                            .frame(width: 96, height: 96)
                            .padding(.vertical, 26)
                        Text("Nine30 Coach").font(.subheadline.weight(.semibold))
                        Text(coach.isOnDevice ? "On-device · Apple Intelligence" : "Offline mode")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    bubble(fromUser: false, text: "How can I help? I can see your recovery, sleep, strain and trends.")

                    ForEach(coach.messages) { m in
                        bubble(fromUser: m.fromUser, text: m.text).id(m.id)
                    }
                    if coach.isThinking {
                        HStack(spacing: 10) {
                            CoachAvatar()
                            ProgressView()
                        }
                    }
                    if coach.messages.isEmpty {
                        GlassEffectContainer(spacing: 8) {
                            VStack(alignment: .trailing, spacing: 8) {
                                ForEach(suggestions, id: \.self) { s in
                                    Button(s) { send(s) }
                                        .buttonStyle(.glass)
                                        .font(.callout)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: coach.messages) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .background { AuroraBackground(accent: Color(hex: 0x8B5CFF), secondary: Color(hex: 0x2FD4FF)) }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var inputBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button { coach.reset() } label: { Image(systemName: "square.and.pencil").frame(width: 24, height: 24) }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                TextField("Ask anything about your data", text: $draft, axis: .vertical)
                    .focused($focused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                    .onSubmit { send(draft) }
                Button { send(draft) } label: { Image(systemName: "arrow.up").font(.headline).frame(width: 24, height: 24) }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(Color(hex: 0x6E7BFF))
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.isThinking)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        draft = ""
        let context = Insights.coachContext(days: store.days, bodyAge: store.bodyAge, profile: store.profile)
        Task { await coach.ask(q, context: context) }
    }

    private func bubble(fromUser: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if fromUser {
                Spacer(minLength: 50)
                Text(text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect(.regular.tint(Color(hex: 0x6E7BFF).opacity(0.35)), in: .rect(cornerRadius: 18))
            } else {
                CoachAvatar()
                Text(text).font(.callout).textSelection(.enabled)
                Spacer(minLength: 20)
            }
        }
    }
}

struct CoachAvatar: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.caption.weight(.bold))
            .frame(width: 28, height: 28)
            .overlay(Circle().strokeBorder(AngularGradient(colors: [Color(hex: 0x6E7BFF), Color(hex: 0x2FD4FF), Color(hex: 0xB28CFF), Color(hex: 0x6E7BFF)], center: .center), lineWidth: 1.5))
    }
}
