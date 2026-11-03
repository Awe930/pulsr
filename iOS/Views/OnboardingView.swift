import SwiftUI

struct OnboardingView: View {
    @Environment(MetricsStore.self) private var store
    @State private var connecting = false

    private let features: [(String, String, String)] = [
        ("heart.text.square", "Recovery", "Daily readiness from overnight HRV, resting heart rate and sleep."),
        ("flame", "Strain", "Cardiovascular load on a 0–21 scale with a target for the day."),
        ("moon.stars", "Sleep", "How much sleep you need tonight and how well you got it."),
        ("waveform.path.ecg", "Stress", "Heart-rate based stress through the day."),
        ("sparkles", "Coach", "Ask questions about your data — answered on device."),
    ]

    var body: some View {
        ZStack {
            AuroraBackground(accent: Color(hex: 0x3D7BFF), secondary: Color(hex: 0xFF4FD8))
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HaloOrb(palette: .spectral, energy: 0.9)
                        .frame(width: 190, height: 190)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
                        .padding(.bottom, 10)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nine30").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Your Apple Watch,\nfully understood.")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("Open source. No subscription. Your health data never leaves your iPhone.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    GlassEffectContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            ForEach(features.indices, id: \.self) { i in
                                let (symbol, title, text) = features[i]
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: symbol)
                                        .font(.title3)
                                        .frame(width: 30)
                                        .foregroundStyle(Theme.green)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(title).font(.headline)
                                        Text(text).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(16)
                                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        Button {
                            connecting = true
                            store.source = .health
                            Task {
                                await store.connect()
                                store.hasOnboarded = true
                                connecting = false
                            }
                        } label: {
                            Label(connecting ? "Connecting…" : "Connect Apple Health", systemImage: "heart.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.green.opacity(0.8))
                        .disabled(!HealthKitSource.isAvailable || connecting)

                        Button {
                            store.source = .demo
                            store.hasOnboarded = true
                        } label: {
                            Text("Explore with demo data")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)

                        Text("Nine30 is not a medical device and does not diagnose anything.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
        }
    }
}
