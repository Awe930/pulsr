import SwiftUI

struct SettingsView: View {
    @Environment(MetricsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = UserProfile()
    @State private var customMaxHR = false
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue
    @AppStorage(Nudges.windDownKey) private var windDownReminder = true
    @AppStorage(Nudges.checkInKey) private var checkInReminder = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Wind down, 1 h before bedtime", isOn: $windDownReminder)
                    Toggle("Morning check-in, 30 min after waking", isOn: $checkInReminder)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Times come from your sleep schedule and update each time you open Nine30. The check-in reminder is skipped once you've checked in.")
                }
                .onChange(of: windDownReminder) { _, _ in Task { await Nudges.refresh(store) } }
                .onChange(of: checkInReminder) { _, _ in Task { await Nudges.refresh(store) } }
                Section("Profile") {
                    TextField("Name", text: $draft.name)
                    Stepper("Age: \(draft.age)", value: $draft.age, in: 14...99)
                    Picker("Sex", selection: $draft.sex) {
                        ForEach(Sex.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Stepper("Sleep goal: \(TimeInterval(draft.sleepGoalHours * 3600).hoursMinutes)", value: $draft.sleepGoalHours, in: 6...10, step: 0.25)
                    Picker("HRV method", selection: $draft.hrvMethod) {
                        ForEach(HRVMethod.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Custom max heart rate", isOn: $customMaxHR)
                    if customMaxHR {
                        Stepper("Max HR: \(draft.maxHeartRateOverride ?? 190) bpm",
                                value: Binding(get: { draft.maxHeartRateOverride ?? 190 }, set: { draft.maxHeartRateOverride = $0 }),
                                in: 140...220)
                    } else {
                        LabeledContent("Estimated max HR", value: "\(Int(draft.maxHeartRate)) bpm")
                    }
                } header: {
                    Text("Scoring")
                } footer: {
                    Text("HRV method: Morning check-in uses your 1-minute Breathe reading (RMSSD) once you have 7 mornings, and falls back to overnight readings on days you skip it. Overnight uses the readings the watch takes while you sleep (SDNN). Max heart rate sets your heart-rate zones; enter yours if you know it from a test or race.")
                }
                Section {
                    Picker("Data source", selection: Binding(get: { store.source }, set: { store.source = $0 })) {
                        Text("Apple Watch (Health)").tag(MetricsStore.Source.health)
                        Text("Demo data").tag(MetricsStore.Source.demo)
                    }
                    Button("Re-request Health access") { Task { await store.connect() } }
                } header: {
                    Text("Data")
                } footer: {
                    Text("To change individual permissions open Settings → Health → Data Access & Devices → Nine30.")
                }
                Section("About") {
                    Link(destination: URL(string: "https://github.com/0xCodez/pulsr")!) {
                        Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    Text("Nine30 is not a medical device. Scores are estimates for wellness purposes only.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuroraBackground(accent: Theme.green) }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        if !customMaxHR { draft.maxHeartRateOverride = nil }
                        store.profile = draft
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            draft = store.profile
            customMaxHR = store.profile.maxHeartRateOverride != nil
        }
    }
}
