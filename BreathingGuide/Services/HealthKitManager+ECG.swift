//
//  HealthKitManager+ECG.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/8/25.
//

import Foundation
import HealthKit

extension HealthKitManager {

    // Lightweight payload for the UI waveform card
    struct ECGSnapshot {
        let classification: String
        let averageHeartRate: Double?
        let date: Date
        /// Downsampled waveform samples for drawing (in volts).
        let samples: [Double]
    }

    /// Latest ECG snapshot for UI. Returns `nil` if unavailable / unauthorized.
    /// - Parameters:
    ///   - seconds: Approximate number of seconds of ECG to keep.
    ///   - maxPoints: Maximum number of waveform samples returned to the UI.
    func fetchLatestECGSnapshot(
        seconds: Double = 10,
        maxPoints: Int = 1200,
        completion: @escaping (ECGSnapshot?) -> Void
    ) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // ECG APIs are only available on iOS 14+
        guard #available(iOS 14.0, *) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let ecgType = HKElectrocardiogramType.electrocardiogramType()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        // 1) Fetch the latest ECG sample
        let sampleQuery = HKSampleQuery(
            sampleType: ecgType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, error in
            guard
                error == nil,
                let ecg = (samples as? [HKElectrocardiogram])?.first,
                let strongSelf = self
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Average HR if present
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            let avgHR = ecg.averageHeartRate?.doubleValue(for: bpmUnit)

            let classificationLabel = strongSelf.classificationString(ecg.classification)

            // 2) Stream the waveform measurements from this ECG
            var rawSamples: [Double] = []

            let samplingFrequencyHz: Double
            if let freqQty = ecg.samplingFrequency {
                samplingFrequencyHz = freqQty.doubleValue(for: .hertz())
            } else {
                // Apple Watch ECG is typically ~512 Hz; use a safe default
                samplingFrequencyHz = 512.0
            }

            let maxRawCount: Int
            if seconds > 0 {
                maxRawCount = Int(seconds * samplingFrequencyHz)
            } else {
                maxRawCount = Int.max
            }

            let waveformQuery = HKElectrocardiogramQuery(ecg) { _, result in
                switch result {
                case .measurement(let measurement):
                    // Use the Apple Watch–style Lead I equivalent on this SDK.
                    if let q = measurement.quantity(for: .appleWatchSimilarToLeadI) {
                        let v = q.doubleValue(for: .volt())
                        rawSamples.append(v)
                    }

                case .done:
                    // Trim and downsample
                    let trimmed = Array(rawSamples.prefix(maxRawCount))
                    let down = strongSelf.downsampleECG(trimmed, to: maxPoints)

                    let snap = ECGSnapshot(
                        classification: classificationLabel,
                        averageHeartRate: avgHR,
                        date: ecg.endDate,
                        samples: down
                    )

                    DispatchQueue.main.async { completion(snap) }

                case .error:
                    DispatchQueue.main.async { completion(nil) }

                @unknown default:
                    // Future-proof: treat any unknown case as failure
                    DispatchQueue.main.async { completion(nil) }
                }
            }

            strongSelf.healthStore.execute(waveformQuery)
        }

        healthStore.execute(sampleQuery)
    }

    // MARK: - Helpers

    /// Simple downsampling: picks evenly spaced points from the raw array.
    private func downsampleECG(_ raw: [Double], to maxPoints: Int) -> [Double] {
        guard maxPoints > 0, raw.count > maxPoints else { return raw }
        let factor = Double(raw.count) / Double(maxPoints)
        var result: [Double] = []
        result.reserveCapacity(maxPoints)

        for i in 0..<maxPoints {
            let idx = Int(Double(i) * factor)
            if idx < raw.count {
                result.append(raw[idx])
            }
        }
        return result
    }

    /// Map ECG classification enum to a user-facing label.
    fileprivate func classificationString(_ c: HKElectrocardiogram.Classification) -> String {
        if #available(iOS 14.0, *) {
            switch c {
            case .notSet:
                return "Not Set"
            case .sinusRhythm:
                return "Sinus Rhythm"
            case .atrialFibrillation:
                return "Atrial Fibrillation"
            case .inconclusiveLowHeartRate:
                return "Inconclusive (Low HR)"
            case .inconclusiveHighHeartRate:
                return "Inconclusive (High HR)"
            case .inconclusivePoorReading:
                return "Inconclusive (Poor Reading)"
            case .inconclusiveOther:
                return "Inconclusive"
            case .unrecognized:
                return "Unrecognized Pattern"
            @unknown default:
                return "Unknown"
            }
        } else {
            return "Unknown"
        }
    }
}
