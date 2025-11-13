//
//  HowItWorksView.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/4/25.
//

import SwiftUI

struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss   // ✅ Enables Close button to work

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What You’ll Need")
                                .font(.headline)
                            Text("• A blood pressure app/device that writes **Systolic** and **Diastolic** to Apple Health.\n• **Heart Rate** in Apple Health (Apple Watch or any HR-capable device/app).\n• Health permissions enabled for BreathingGuide to **read** BP/HR (and optional SpO₂, ECG).")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Before You Start")
                                .font(.headline)
                            Text("1) Open your BP app and take a fresh reading.\n2) In BreathingGuide’s first screen, tap **Refresh Vitals** to pull the latest values from Apple Health.\n3) Pick your **session duration** and tap **Start Breathing Exercise**.")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("During the Session")
                                .font(.headline)
                            Text("• Follow the on-screen cue (Inhale / Hold / Exhale). The circle gently swells and the ocean sound rises/falls with your breath.\n• You can choose different **breathing patterns** from the top menu. Tap **?** to see what each pattern means.\n• Voice prompts use your selected voice (e.g., Ava) and say “Inhale / Hold / Exhale” at the start of each phase.")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("After the Session")
                                .font(.headline)
                            Text("• The summary shows your **Before** values and lets you **Re-check** to capture **After** readings for comparison.\n• You can also review a **7-day health summary** (BP/HR; optional SpO₂ and ECG when authorized).")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Health Permissions")
                                .font(.headline)
                            Text("If any values are missing (e.g., SpO₂ or ECG), enable read permission in the Health app:\n• Open **Health** > **Browse** > (Blood Pressure / Heart / Respiratory) > **Data Sources & Access** > **Apps** > **BreathingGuide** > Allow **Read**.\n\n**We only read your existing data**. No writes unless you explicitly use a save feature.")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Custom Voice & Enhanced Voices")
                                .font(.headline)
                            Text("• Go to **Settings** > **Accessibility** > **Spoken Content** > **Voices** > **English** and download your preferred **Enhanced** voice (e.g., **Ava (Enhanced)**).\n• In the app, open **Voice & Sound** (waveform icon) and choose your voice, rate, pitch, and volume. Ava is the default if available.\n• If the phone ever speaks with a different voice, open **Voice & Sound** and tap **Test Voice** to confirm your selection.")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Supported Devices & Apps")
                                .font(.headline)
                            Text("Most mainstream cuffs/apps work as long as they write standard HealthKit types:\n• **Blood Pressure** correlation (Systolic + Diastolic)\n• **Heart Rate** samples\n• Optional: **Blood Oxygen (SpO₂)** and **ECG** (Apple Watch)\n\nIf your values show up in the Health app, BreathingGuide can read them once permission is granted.")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Troubleshooting")
                                .font(.headline)
                            Text("• **Numbers don’t change?** Take a fresh BP in your cuff app, then tap **Refresh Vitals** here.\n• **Missing SpO₂/ECG?** Enable read permission for these in Health.\n• **Voice sounds off?** Ensure your voice is downloaded (Enhanced if available) and re-select it in **Voice & Sound**.")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("How It Works")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()   // ✅ Now dismisses properly when tapped
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
