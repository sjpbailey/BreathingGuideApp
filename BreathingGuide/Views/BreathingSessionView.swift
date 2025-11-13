//
//  BreathingSessionView.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/4/25.

import SwiftUI
import AVFoundation

enum BreathPhase { case inhale, hold, exhale }

enum BreathingPreset: String, CaseIterable, Identifiable {
    case custom     = "Custom"
    case rectangle  = "Rectangle"
    case ujjayi     = "Ujjayi"
    case fourSevenEight = "4-7-8"
    case box444     = "Box 4-4-4"
    case box555     = "Box 5-5-5"
    case triangle   = "Triangle"

    var id: String { rawValue }

    /// Default (inhale, hold, exhale)
    var pattern: (Double, Double, Double) {
        switch self {
        case .custom:         return (8, 0, 8)
        case .rectangle:      return (4, 0, 4)
        case .ujjayi:         return (8, 0, 8)
        case .fourSevenEight: return (4, 7, 8)
        case .box444:         return (4, 4, 4)
        case .box555:         return (5, 5, 5)
        case .triangle:       return (3, 3, 3)
        }
    }
}

struct BreathingSessionView: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    // Inputs from MeasureVitalsView
    let totalSessionSeconds: Int
    let beforeSystolic: Double?
    let beforeDiastolic: Double?
    let beforeHeartRate: Double?
    let staleOnLaunch: Bool   // drives the non-blocking banner

    // Session state
    @State private var phase: BreathPhase = .inhale
    @State private var isRunning = false
    @State private var remainingSeconds: Int
    @State private var showSummary = false

    // Preset + sliders (1..15s)
    @State private var preset: BreathingPreset = .custom
    @State private var inhaleSeconds: Double = 8
    @State private var pauseSeconds:  Double = 0
    @State private var exhaleSeconds: Double = 8

    // Phase timing/progress
    @State private var phaseProgress: CGFloat = 0
    @State private var phaseRemaining: Double = 0

    // Timer using real elapsed time
    @State private var timer: Timer?
    @State private var lastTick: CFTimeInterval = 0
    @State private var secondAccumulator: Double = 0

    // Track what comes after a hold (for box vs non-box)
    @State private var nextAfterHold: BreathPhase = .exhale

    // Voice (Ava forced by engine)
    private let voice = VoicePromptEngine()
    @AppStorage("voice_prompts_enabled") private var voicePromptsEnabled: Bool = true
    @AppStorage("voice_rate")  private var voiceRate: Double = 0.38
    @AppStorage("voice_pitch") private var voicePitch: Double = 1.00
    @AppStorage("voice_volume")private var voiceVolume: Double = 0.65
    @AppStorage("voice_lead_time") private var voiceLeadTime: Double = 0.00

    // Ambient ocean sound
    @AppStorage("ambient_enabled")     private var ambientEnabled: Bool = true
    @AppStorage("ambient_base_volume") private var ambientBase: Double = 0.08
    @AppStorage("ambient_peak_volume") private var ambientPeak: Double = 0.35
    @State private var ambientPlayer: AVAudioPlayer?
    @State private var ambientCurrentVolume: Float = 0.0
    private let ambientSmoothing: Float = 0.15

    // Visuals
    @State private var phaseCrossfade: Double = 1.0
    @State private var phaseTextOpacity: Double = 1.0

    // Help + banner
    @State private var showHelp = false
    @State private var showStaleOverlay = false

    init(
        healthKitManager: HealthKitManager,
        totalSessionSeconds: Int,
        beforeSystolic: Double?,
        beforeDiastolic: Double?,
        beforeHeartRate: Double?,
        staleOnLaunch: Bool = false
    ) {
        self.healthKitManager = healthKitManager
        self.totalSessionSeconds = max(1, totalSessionSeconds)
        self.beforeSystolic = beforeSystolic
        self.beforeDiastolic = beforeDiastolic
        self.beforeHeartRate = beforeHeartRate
        self.staleOnLaunch = staleOnLaunch
        _remainingSeconds = State(initialValue: max(1, totalSessionSeconds))
    }

    // MARK: - BODY

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // Top bar: Back + Preset picker + Help (NO voice button)
                HStack {
                    Button { endSessionAndDismiss() } label: {
                        HStack(spacing: 6) { Image(systemName: "chevron.left"); Text("Back") }
                            .font(.headline)
                    }
                    Spacer()

                    // Preset menu
                    Menu {
                        Picker("Breathing Type", selection: $preset) {
                            ForEach(BreathingPreset.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wind")
                            Text(preset.rawValue).lineLimit(1)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                    .disabled(isRunning)
                    .onChange(of: preset) { _, newValue in
                        applyPreset(newValue)
                        handleTimingChange()   // reset to inhale when preset changes (if not running)
                    }

                    // Help "?"
                    Button { showHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                            .imageScale(.large)
                            .accessibilityLabel("Breathing Methods Help")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)

                // BEFORE vitals
                VStack(spacing: 2) {
                    Text("BP Before: \(bpString((beforeSystolic, beforeDiastolic)))").font(.headline)
                    Text("HR Before: \(hrString(beforeHeartRate))").font(.headline)
                }

                // Animated circle
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: phaseGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 220 + circleScale * 50, height: 220 + circleScale * 50)
                        .shadow(color: Color.black.opacity(0.15), radius: 16)
                        .animation(.easeInOut(duration: currentPhaseDuration), value: circleScale)

                    Text(phaseTitle)
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundColor(.white)
                        .shadow(radius: 1)
                        .opacity(phaseTextOpacity)
                        .animation(.easeInOut(duration: 0.15), value: phaseTextOpacity)
                }
                .opacity(phaseCrossfade)
                .animation(.easeInOut(duration: 0.12), value: phaseCrossfade)
                .frame(height: 260)

                // Progress bar
                progressBar

                // Sliders (lock while running)
                Group {
                    sliderRow(title: "Inhale", value: $inhaleSeconds)
                    sliderRow(title: "Hold",   value: $pauseSeconds)
                    sliderRow(title: "Exhale", value: $exhaleSeconds)
                }
                .disabled(isRunning)
                // If user tweaks timings while paused, restart cycle from Inhale
                .onChange(of: inhaleSeconds) { _, _ in handleTimingChange() }
                .onChange(of: pauseSeconds)  { _, _ in handleTimingChange() }
                .onChange(of: exhaleSeconds) { _, _ in handleTimingChange() }

                // Buttons
                HStack(spacing: 12) {
                    Button { toggleStart() } label: {
                        Text(isRunning ? "Pause" : "Start")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(isRunning ? Color.orange.opacity(0.25) : Color.blue)
                            .foregroundColor(isRunning ? .orange : .white)
                            .cornerRadius(12)
                    }
                    Button(role: .destructive) { presentSummary() } label: {
                        Text("End Session")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)

                // Time remaining
                Text("Time Remaining: \(timeString(remainingSeconds))")
                    .font(.title3).bold()
                    .padding(.top, 2)

                // Gentle guidance text at the bottom
                Text("Relax your shoulders, jaw, and belly. Pause anytime to adjust the times, then tap Start to begin again from Inhale.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .padding(.top, 4)

                Spacer(minLength: 6)
            }
            .padding(.top, 8)        // extra top space so nothing is clipped
            .padding(.bottom, 16)    // room at bottom for the text
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .spokenAudio, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true, options: [])

            // Apply voice prefs to engine (Ava forced internally)
            voice.setPrefs(VoicePrefs(voiceID: nil,
                                      rate:  Float(voiceRate),
                                      pitch: Float(voicePitch),
                                      volume: Float(voiceVolume)))

            applyPreset(preset)
            resetPhaseForNewRun()
            loadAmbient()

            // show banner if they didn’t refresh on the prior screen
            showStaleOverlay = staleOnLaunch
        }
        .onDisappear {
            stopTimer()
            voice.stop()
            stopAmbient()
        }
        .sheet(isPresented: $showSummary) {
            SessionSummaryView(
                healthKitManager: healthKitManager,
                bpBefore: (beforeSystolic, beforeDiastolic),
                hrBefore: beforeHeartRate
            )
        }
        .sheet(isPresented: $showHelp) {
            BreathingHelpSheetView()
        }
        // Non-blocking stale banner
        .overlay(alignment: .top) {
            if showStaleOverlay {
                VStack {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fresh BP/HR recommended")
                                .font(.headline)
                            Text("Open your BP app and take a new measurement, then tap Refresh on the first screen next time. You can continue this session with your last saved values.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button {
                            withAnimation { showStaleOverlay = false }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .imageScale(.large)
                        }
                        .accessibilityLabel("Dismiss")
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - UI bits

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color(.systemGray5)).frame(height: 12)
            Capsule()
                .fill(LinearGradient(colors: [Color.blue.opacity(0.7), Color.pink.opacity(0.7)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: progressWidth, height: 12)
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
        .animation(.linear(duration: 0.05), value: phaseProgress)
    }

    private func sliderRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.headline)
            Slider(value: value, in: 1...15, step: 1)
                .tint(.blue)
                .padding(.horizontal, 8)
            Text("\(Int(value.wrappedValue))s")
                .font(.headline)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    // MARK: - Phase / Animation

    private var phaseTitle: String {
        switch phase {
        case .inhale: return "Inhale"
        case .hold:   return "Hold"
        case .exhale: return "Exhale"
        }
    }

    private var currentPhaseDuration: Double {
        switch phase {
        case .inhale: return inhaleSeconds
        case .hold:   return pauseSeconds
        case .exhale: return exhaleSeconds
        }
    }

    private var circleScale: CGFloat {
        switch phase {
        case .inhale: return 1.0 + CGFloat(phaseProgress) * 0.35
        case .hold:   return 1.35
        case .exhale: return 1.35 - CGFloat(phaseProgress) * 0.35
        }
    }

    private var phaseGradient: [Color] {
        switch phase {
        case .inhale: return [Color.blue, Color.cyan]
        case .hold:   return [Color.gray.opacity(0.4), Color.purple.opacity(0.3)]
        case .exhale: return [Color.pink, Color.mint.opacity(0.3)]
        }
    }

    private var progressWidth: CGFloat {
        let totalW = UIScreen.main.bounds.width - 48
        return CGFloat(phaseProgress) * totalW
    }

    // MARK: - Preset behavior

    private var holdAfterExhale: Bool {
        switch preset {
        case .box444, .box555: return true
        default:               return false
        }
    }

    private func applyPreset(_ p: BreathingPreset) {
        var (i, h, e) = p.pattern
        if p == .rectangle || p == .ujjayi { h = 0 }   // force no-hold
        inhaleSeconds = i
        pauseSeconds  = h
        exhaleSeconds = e
    }

    // When timings/preset change while paused, restart cycle cleanly at Inhale.
    private func handleTimingChange() {
        guard !isRunning else { return }   // don’t disturb active session
        resetPhaseForNewRun()
    }

    // MARK: - Visual helpers

    private func performPauseCrossfade(duration: Double) {
        let dip = 0.6
        withAnimation(.easeInOut(duration: duration / 2)) { phaseCrossfade = dip }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration / 2) {
            withAnimation(.easeInOut(duration: duration / 2)) { phaseCrossfade = 1.0 }
        }
    }

    private func fadePhaseText() {
        phaseTextOpacity = 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.15)) { phaseTextOpacity = 1.0 }
        }
    }

    // MARK: - Controls

    private func toggleStart() { isRunning ? pauseTimer() : startTimer() }

    private func startTimer() {
        guard timer == nil else { return }
        isRunning = true
        if phaseRemaining <= 0 { resetPhaseForNewRun() }
        secondAccumulator = 0

        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            let now = CACurrentMediaTime()
            let dt = now - lastTick
            lastTick = now
            tick(dt: dt)
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)

        if voicePromptsEnabled { speakAligned(phase) }
        if ambientEnabled     { ambientPlayer?.play() }
    }

    private func pauseTimer() {
        isRunning = false
        stopTimer()
        voice.stop()
        ambientPlayer?.pause()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func resetPhaseForNewRun() {
        phase = .inhale
        phaseRemaining = max(0.001, inhaleSeconds)
        phaseProgress = 0
        phaseCrossfade = 1.0
        phaseTextOpacity = 1.0
        nextAfterHold = .exhale
        updateAmbientVolume()
    }

    private func tick(dt: Double) {
        guard isRunning else { return }

        // Total session countdown
        secondAccumulator += dt
        while secondAccumulator >= 1.0 {
            if remainingSeconds > 0 { remainingSeconds -= 1 }
            secondAccumulator -= 1.0
        }
        if remainingSeconds <= 0 {
            presentSummary()
            return
        }

        // Phase timing
        phaseRemaining -= dt
        let total = max(0.001, currentPhaseDuration)
        phaseProgress = CGFloat(max(0, min(1, 1.0 - (phaseRemaining / total))))

        updateAmbientVolume()

        if phaseRemaining <= 0 {
            advancePhase()
        }
    }

    private func advancePhase() {
        switch phase {
        case .inhale:
            if pauseSeconds > 0 {
                nextAfterHold = .exhale
                phase = .hold
                phaseRemaining = max(0.001, pauseSeconds)
                performPauseCrossfade(duration: min(0.3, pauseSeconds))
                fadePhaseText()
                speakAligned(.hold)
            } else {
                phase = .exhale
                phaseRemaining = max(0.001, exhaleSeconds)
                fadePhaseText()
                speakAligned(.exhale)
            }

        case .exhale:
            if pauseSeconds > 0, holdAfterExhale {
                nextAfterHold = .inhale
                phase = .hold
                phaseRemaining = max(0.001, pauseSeconds)
                performPauseCrossfade(duration: min(0.3, pauseSeconds))
                fadePhaseText()
                speakAligned(.hold)
            } else {
                phase = .inhale
                phaseRemaining = max(0.001, inhaleSeconds)
                fadePhaseText()
                speakAligned(.inhale)
            }

        case .hold:
            phase = nextAfterHold
            phaseRemaining = max(0.001, (phase == .inhale ? inhaleSeconds : exhaleSeconds))
            fadePhaseText()
            speakAligned(phase)
        }

        phaseProgress = 0
        updateAmbientVolume()
    }

    // MARK: - Ambient ocean helpers

    private func loadAmbient() {
        guard ambientEnabled, ambientPlayer == nil else { return }
        ambientPlayer = audioPlayer(named: "ocean", ext: "wav") ?? audioPlayer(named: "ocean", ext: "mp3")
        ambientPlayer?.numberOfLoops = -1
        ambientPlayer?.volume = Float(ambientBase)
    }

    private func stopAmbient() {
        ambientPlayer?.stop()
        ambientPlayer = nil
    }

    private func ambientEnvelope() -> Float {
        switch phase {
        case .inhale: return Float(phaseProgress)       // rise
        case .hold:   return 0.35                       // settle
        case .exhale: return 1.0 - Float(phaseProgress) // fall
        }
    }

    private func updateAmbientVolume() {
        guard ambientEnabled, let p = ambientPlayer else { return }
        let minV = max(0.0, min(1.0, ambientBase))
        let maxV = max(0.0, min(1.0, ambientPeak))
        let env  = ambientEnvelope()
        let target = Float(minV + (maxV - minV) * Double(env))
        ambientCurrentVolume = ambientCurrentVolume + ambientSmoothing * (target - ambientCurrentVolume)
        p.volume = max(0.0, min(1.0, ambientCurrentVolume))
    }

    private func audioPlayer(named: String, ext: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: named, withExtension: ext) else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }

    // MARK: - Voice helpers

    private func speakAligned(_ p: BreathPhase) {
        guard voicePromptsEnabled else { return }
        if voiceLeadTime > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + voiceLeadTime) { self.speak(p) }
        } else {
            speak(p)
        }
    }

    private func speak(_ p: BreathPhase) {
        switch p {
        case .inhale: voice.inhale()
        case .exhale: voice.exhale()
        case .hold:   if pauseSeconds > 0 { voice.hold() }
        }
    }

    // MARK: - Finish / Summary

    private func endSessionAndDismiss() {
        pauseTimer()
        dismiss()
    }

    private func presentSummary() {
        pauseTimer()
        showSummary = true
    }

    // MARK: - Formatters

    private func bpString(_ bp: (Double?, Double?)) -> String {
        let s = bp.0.flatMap { $0 > 0 ? Int($0.rounded()) : nil }
        let d = bp.1.flatMap { $0 > 0 ? Int($0.rounded()) : nil }
        switch (s, d) {
        case let (sv?, dv?): return "\(sv) / \(dv) mmHg"
        case (nil, nil):     return "-- / -- mmHg"
        case let (sv?, nil): return "\(sv) / -- mmHg"
        case let (nil, dv?): return "-- / \(dv) mmHg"
        }
    }

    private func hrString(_ v: Double?) -> String {
        guard let x = v, x > 0 else { return "-- bpm" }
        return "\(Int(x.rounded())) bpm"
    }

    private func timeString(_ s: Int) -> String {
        let v = max(0, s)
        return "\(v / 60)m \(v % 60)s"
    }
}

// MARK: - Help Sheet
private struct BreathingHelpSheetView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("How Breathing Types Work") {
                    LabeledContent("Custom", value: "Use sliders. Commonly 1:2 inhale:exhale.")
                    LabeledContent("Rectangle", value: "Inhale up, exhale across. No hold.")
                    LabeledContent("Ujjayi", value: "Gentle ocean sound in the throat. No hold.")
                    LabeledContent("4–7–8", value: "Inhale 4 • Hold 7 • Exhale 8.")
                    LabeledContent("Box 4–4–4", value: "Inhale 4 • Hold 4 • Exhale 4 • Hold 4.")
                    LabeledContent("Box 5–5–5", value: "Inhale 5 • Hold 5 • Exhale 5 • Hold 5.")
                    LabeledContent("Triangle", value: "Inhale 3 • Hold 3 • Exhale 3.")
                }
                Section("Tips") {
                    Text("Match the circle and voice. If you didn’t take a fresh BP, you can still continue—watch for the banner reminder at the top.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Breathing Methods")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismissSheet() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @Environment(\.dismiss) private var dismissSheet
}
