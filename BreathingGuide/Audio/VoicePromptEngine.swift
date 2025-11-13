//
//  VoicePromptEngine.swift
//  BreathingGuide
//
//  Brute-force: Every utterance explicitly selects Ava (Enhanced if available)
//  so the system can’t fall back to Samantha on cold starts.
//

import Foundation
import AVFoundation

struct VoicePrefs {
    var voiceID: String?
    var rate:  Float = 0.38
    var pitch: Float = 1.00
    var volume: Float = 0.65
}

final class VoicePromptEngine {
    private let synth = AVSpeechSynthesizer()
    private(set) var prefs = VoicePrefs()

    // Cached preference, but we’ll still *resolve Ava on every utterance*
    private var preferredVoiceID: String?

    // MARK: - Public API

    func setVoice(byIdentifier id: String?) {
        preferredVoiceID = id
    }

    func setPrefs(_ new: VoicePrefs) {
        self.prefs = new
        self.preferredVoiceID = new.voiceID
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    func inhale() { speak("Inhale") }
    func exhale() { speak("Exhale") }
    func hold()   { speak("Hold") }

    // MARK: - Core speaking

    private func speak(_ text: String) {
        DispatchQueue.main.async {
            // Resolve the actual voice to use *right now*.
            let v = self.resolveAvaOrSelectedVoice()

            // Prime once *with that exact voice* so the very first word is correct.
            self.primeOnce(with: v)

            let u = AVSpeechUtterance(string: text)
            u.voice = v                                    // <-- hard bind the voice every time
            u.rate  = max(0.2, min(0.6, self.prefs.rate))
            u.pitchMultiplier = self.prefs.pitch
            u.volume = max(0.0, min(1.0, self.prefs.volume))
            self.synth.speak(u)
        }
    }

    // Resolve the voice each time. Prefer:
    // 1) The user’s selected voiceID (if valid)
    // 2) Ava (Enhanced)
    // 3) Ava (any)
    // 4) en-US system fallback (last resort)
    private func resolveAvaOrSelectedVoice() -> AVSpeechSynthesisVoice {
        if let id = preferredVoiceID, let v = AVSpeechSynthesisVoice(identifier: id) {
            return v
        }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let avaEnhanced = voices.first(where: { $0.language.hasPrefix("en") && $0.name.contains("Ava") && $0.quality == .enhanced }) {
            return avaEnhanced
        }
        if let avaAny = voices.first(where: { $0.language.hasPrefix("en") && $0.name.contains("Ava") }) {
            return avaAny
        }
        return AVSpeechSynthesisVoice(language: "en-US") ?? AVSpeechSynthesisVoice()
    }

    // Prime so the *first* real word uses the chosen voice (prevents cold-start fallback).
    private var didPrimeForCurrentSession = false
    private func primeOnce(with voice: AVSpeechSynthesisVoice) {
        guard !didPrimeForCurrentSession else { return }
        didPrimeForCurrentSession = true

        let u = AVSpeechUtterance(string: " ")
        u.voice = voice
        u.rate  = max(0.2, min(0.6, prefs.rate))
        u.pitchMultiplier = prefs.pitch
        u.volume = 0.01
        u.preUtteranceDelay = 0
        u.postUtteranceDelay = 0
        synth.speak(u)
    }

    static func displayName(for v: AVSpeechSynthesisVoice) -> String {
        var label = v.name
        if v.quality == .enhanced { label += " (Enhanced)" }
        return label
    }
}
