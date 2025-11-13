//
//  HealthKitManager+Summary.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/8/25.

//
//  HealthKitManager+Summary.swift
//  BreathingGuide
//
//  Read-only helpers used by HealthSummaryView:
//  • Last 7 days BP (latest pair per day)
//  • Last 7 days HR (min/avg/max per day)
//  • Latest SpO₂ (looks back up to 30 days by default)
//  • Latest ECG classification + date (iOS 14+)
//

import Foundation
import HealthKit

extension HealthKitManager {

    // MARK: - Types

    struct HRDaySummary: Identifiable {
        let id = UUID()
        let date: Date
        let min: Double
        let avg: Double
        let max: Double
    }

    // MARK: - Last 7 days BP (latest pair per day)

    func fetchLast7DaysBloodPressure(
        completion: @escaping ([(date: Date, systolic: Double, diastolic: Double)]) -> Void
    ) {
        guard
            let bpCorrType = HKObjectType.correlationType(forIdentifier: .bloodPressure),
            let sysType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
            let diaType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)
        else { DispatchQueue.main.async { completion([]) }; return }

        let now = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -7, to: now) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let q = HKSampleQuery(
            sampleType: bpCorrType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samplesOrNil, errorOrNil in
            guard errorOrNil == nil, let samples = samplesOrNil as? [HKCorrelation] else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let mmHg = HKUnit.millimeterOfMercury()
            var picked: [Date: (Double, Double)] = [:]

            for corr in samples {
                let day = Calendar.current.startOfDay(for: corr.startDate)
                if picked[day] != nil { continue } // already grabbed the latest for that day

                let sys = (corr.objects(for: sysType).first as? HKQuantitySample)?.quantity.doubleValue(for: mmHg)
                let dia = (corr.objects(for: diaType).first as? HKQuantitySample)?.quantity.doubleValue(for: mmHg)
                if let s = sys, let d = dia { picked[day] = (s, d) }
            }

            let result = picked.keys.sorted().map { day in
                let pair = picked[day]!
                return (date: day, systolic: pair.0, diastolic: pair.1)
            }

            DispatchQueue.main.async { completion(result) }
        }

        healthStore.execute(q)
    }

    // MARK: - Last 7 days HR (min/avg/max per day)

    func fetchLast7DaysHeartRateSummary(
        completion: @escaping ([HRDaySummary]) -> Void
    ) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let now = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -7, to: now) else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let q = HKSampleQuery(
            sampleType: hrType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samplesOrNil, errorOrNil in
            guard errorOrNil == nil, let samples = samplesOrNil as? [HKQuantitySample] else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let unit = HKUnit.count().unitDivided(by: .minute())
            var buckets: [Date: [Double]] = [:]

            for s in samples {
                let day = Calendar.current.startOfDay(for: s.startDate)
                let bpm = s.quantity.doubleValue(for: unit)
                buckets[day, default: []].append(bpm)
            }

            let summaries: [HRDaySummary] = buckets.keys.sorted().map { day in
                let vals = buckets[day]!
                let minV = vals.min() ?? 0
                let maxV = vals.max() ?? 0
                let avgV = vals.reduce(0, +) / Double(vals.count)
                return HRDaySummary(date: day, min: minV, avg: avgV, max: maxV)
            }

            DispatchQueue.main.async { completion(summaries) }
        }

        healthStore.execute(q)
    }

    // MARK: - Latest SpO₂ (looks back up to N days; default 30)

    func fetchLatestSpO2(lookbackDays: Int = 30, completion: @escaping (Double?, Date?) -> Void) {
        guard let spo2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) else {
            DispatchQueue.main.async { completion(nil, nil) }
            return
        }

        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let q = HKSampleQuery(
            sampleType: spo2Type,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samplesOrNil, _ in
            guard let s = (samplesOrNil as? [HKQuantitySample])?.first else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }
            let pct = s.quantity.doubleValue(for: HKUnit.percent()) * 100.0
            DispatchQueue.main.async { completion(pct, s.startDate) }
        }

        healthStore.execute(q)
    }

    // MARK: - Latest ECG (classification + date), iOS 14+

    func fetchLatestECG(completion: @escaping (_ classification: String?, _ date: Date?) -> Void) {
        guard #available(iOS 14.0, *) else {
            DispatchQueue.main.async { completion(nil, nil) }
            return
        }

        let ecgType = HKObjectType.electrocardiogramType()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let q = HKSampleQuery(
            sampleType: ecgType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samplesOrNil, _ in
            guard
                #available(iOS 14.0, *),
                let ecg = (samplesOrNil as? [HKElectrocardiogram])?.first
            else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }

            // Baseline-safe mapping; unknown cases collapse to default.
            let label: String
            switch ecg.classification {
            case .notSet:             label = "Not Set"
            case .sinusRhythm:        label = "Sinus Rhythm"
            case .atrialFibrillation: label = "Atrial Fibrillation"
            default:                  label = "Other / Unknown"
            }

            DispatchQueue.main.async { completion(label, ecg.startDate) }
        }

        healthStore.execute(q)
    }
}
