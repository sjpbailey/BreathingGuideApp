//
//  BreathAudioEngine.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/7/25.
//
//  Plays inhale/exhale audio stretched to exactly match a target duration,
//  using AVAudioEngine + AVAudioUnitVarispeed.
//  Drop inhale.wav / exhale.wav in your app bundle (Audio group).
//

import AVFoundation

final class BreathAudioEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed() // rate 0.25 ... 4.0

    private var inhaleFile: AVAudioFile?
    private var exhaleFile: AVAudioFile?

    init() {
        engine.attach(player)
        engine.attach(varispeed)
        engine.connect(player, to: varispeed, format: nil)
        engine.connect(varispeed, to: engine.mainMixerNode, format: nil)

        do {
            try engine.start()
        } catch {
            print("BreathAudioEngine: failed to start engine:", error)
        }

        if let uInhale = Bundle.main.url(forResource: "inhale", withExtension: "wav") {
            inhaleFile = try? AVAudioFile(forReading: uInhale)
        }
        if let uExhale = Bundle.main.url(forResource: "exhale", withExtension: "wav") {
            exhaleFile = try? AVAudioFile(forReading: uExhale)
        }
    }

    enum Kind { case inhale, exhale }

    func stop() {
        player.stop()
    }

    /// Play inhale/exhale stretched to fill `target` seconds.
    /// Limits rate to a safe range to avoid artifacts.
    func play(kind: Kind, target: TimeInterval, fadeOut: TimeInterval = 0.08) {
        let file = (kind == .inhale) ? inhaleFile : exhaleFile
        guard let file else { return }

        let sr = file.processingFormat.sampleRate
        let frames = AVAudioFrameCount(file.length)
        let sourceDuration = Double(frames) / sr

        // playbackRate < 1.0 -> slower (longer), > 1.0 -> faster (shorter)
        let clampedTarget = max(0.05, target)
        var rate = sourceDuration / clampedTarget
        rate = min(max(rate, 0.25), 4.0)
        varispeed.rate = Float(rate)

        player.stop()
        player.scheduleFile(file, at: nil, completionHandler: nil)
        if !engine.isRunning {
            try? engine.start()
        }
        player.play()

        // Soft fade-out to avoid clicks if we cut it right at boundary.
        if clampedTarget > fadeOut {
            DispatchQueue.main.asyncAfter(deadline: .now() + (clampedTarget - fadeOut)) { [weak self] in
                self?.fadeOut(duration: fadeOut)
            }
        }
    }

    private func fadeOut(duration: TimeInterval) {
        guard duration > 0 else { return }
        let steps = 12
        let dt = duration / Double(steps)
        var step = 0
        let initial = engine.mainMixerNode.outputVolume
        Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            step += 1
            let p = Double(step) / Double(steps)
            self.engine.mainMixerNode.outputVolume = Float((1.0 - p)) * initial
            if step >= steps {
                t.invalidate()
                self.player.stop()
                self.engine.mainMixerNode.outputVolume = 1.0
            }
        }
    }
}

