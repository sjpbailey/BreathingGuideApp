//
//  VoiceSettingsView.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/7/25.

import SwiftUI
import AVFoundation

struct VoiceSettingsView: View {
    @AppStorage("voice_id")      private var voiceID: String?
    @AppStorage("voice_rate")    private var voiceRate: Double = 0.38
    @AppStorage("voice_pitch")   private var voicePitch: Double = 1.00
    @AppStorage("voice_volume")  private var voiceVolume: Double = 0.65
    @AppStorage("voice_prompts_enabled") private var voiceEnabled: Bool = true
    @AppStorage("did_set_default_voice") private var didSetDefaultVoice: Bool = false

    @State private var selectedVoiceID: String?

    private var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            Section(header: Text("Voice Prompts")) {
                Toggle("Enable Voice Prompts", isOn: $voiceEnabled)
            }

            Section(header: Text("Voice")) {
                Picker("Voice", selection: Binding(
                    get: { selectedVoiceID ?? "" },
                    set: { newValue in
                        selectedVoiceID = newValue.isEmpty ? nil : newValue
                        voiceID = selectedVoiceID
                    }
                )) {
                    ForEach(englishVoices, id: \.identifier) { v in
                        Text(Self.displayName(for: v)).tag(v.identifier)
                    }
                }
            }

            Section(header: Text("Tuning")) {
                HStack { Text("Rate");  Slider(value: $voiceRate,  in: 0.2...0.6, step: 0.01) }
                HStack { Text("Pitch"); Slider(value: $voicePitch, in: 0.8...1.2, step: 0.01) }
                HStack { Text("Volume");Slider(value: $voiceVolume, in: 0.2...1.0, step: 0.01) }
                Text("Ava is the default. Changes apply on the next session start.")
                    .font(.footnote).foregroundColor(.secondary)
            }

            Section(header: Text("Test")) {
                Button("Test Voice (Inhale • Hold • Exhale)") {
                    testVoice()
                }
            }
        }
        .navigationTitle("Voice & Sound")
        .onAppear {
            // One-time default only: if no saved voice, choose Ava (Enhanced if available)
            if voiceID == nil && !didSetDefaultVoice {
                let voices = AVSpeechSynthesisVoice.speechVoices()
                let avaEnhanced = voices.first { $0.language.hasPrefix("en") && $0.name.contains("Ava") && $0.quality == .enhanced }
                let avaAny      = voices.first { $0.language.hasPrefix("en") && $0.name.contains("Ava") }
                if let ava = (avaEnhanced ?? avaAny) {
                    voiceID = ava.identifier
                    didSetDefaultVoice = true
                }
            }
            selectedVoiceID = voiceID
        }
    }

    static func displayName(for v: AVSpeechSynthesisVoice) -> String {
        var label = v.name
        if v.quality == .enhanced { label += " (Enhanced)" }
        return label
    }

    // Local voice test
    private func testVoice() {
        let synth = AVSpeechSynthesizer()
        let voice = (selectedVoiceID ?? voiceID).flatMap { AVSpeechSynthesisVoice(identifier: $0) }
                 ?? AVSpeechSynthesisVoice(language: "en-US")

        func speak(_ text: String) {
            let u = AVSpeechUtterance(string: text)
            u.voice = voice
            u.rate  = max(0.2, min(0.6, Float(voiceRate)))
            u.pitchMultiplier = Float(voicePitch)
            u.volume = max(0.0, min(1.0, Float(voiceVolume)))
            synth.speak(u)
        }

        // Prime once so the first word uses the selected voice
        let prime = AVSpeechUtterance(string: " ")
        prime.voice = voice
        prime.volume = 0.01
        synth.speak(prime)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            speak("Inhale")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { speak("Hold") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { speak("Exhale") }
        }
    }
}
