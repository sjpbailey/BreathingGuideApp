//
//  AmbientSoundEngine.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/7/25.
//
//
//  AmbientSoundEngine.swift
//  BreathingGuide
//
//  Simple looped ambience (ocean or wind). Use .start(type:volume:) and .stop().
//  Call .duck(to:) temporarily while speaking, then .duck(to:) back to normal.
//

import AVFoundation

enum AmbientType: String, CaseIterable {
    case none
    case ocean
    case wind

    var filename: String? {
        switch self {
        case .none:  return nil
        case .ocean: return "ocean_loop"
        case .wind:  return "wind_loop"
        }
    }
}

final class AmbientSoundEngine {
    private var player: AVAudioPlayer?
    private(set) var type: AmbientType = .none
    private(set) var baseVolume: Float = 0.35

    func start(type: AmbientType, volume: Float) {
        stop()
        self.type = type
        self.baseVolume = volume

        guard let name = type.filename,
              let url = Bundle.main.url(forResource: name, withExtension: "mp3")
                    ?? Bundle.main.url(forResource: name, withExtension: "wav") else {
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = volume
            p.prepareToPlay()
            p.play()
            self.player = p

            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AmbientSoundEngine error: \(error.localizedDescription)")
        }
    }

    func updateVolume(_ volume: Float) {
        baseVolume = volume
        player?.volume = volume
    }

    /// Temporarily lower (or raise back) the volume during speech.
    func duck(to fraction: Float) {
        guard let p = player else { return }
        let target = max(0, min(1, baseVolume * fraction))
        p.setVolume(target, fadeDuration: 0.08)
    }

    func stop() {
        player?.stop()
        player = nil
        type = .none
    }
}
