//
//  HealthKitManager.swift
//  BreathingGuide
//
//  HealthKitManager.swift
//  BreathingGuide
//
//  Read-only HealthKit manager.
//  Requests READ access for: Blood Pressure (sys/dia), Heart Rate, SpO₂, ECG (iOS 14+).
//  Provides latest BP/HR fetchers and a convenience fetchLatestVitals().
//  Includes optional saveSessionResults(...) (unchanged).
//

import Foundation
import HealthKit
import Combine

final class HealthKitManager: ObservableObject {

    // MARK: - Public state
    let healthStore = HKHealthStore()

    @Published var systolic: Double?
    @Published var diastolic: Double?
    @Published var heartRate: Double?

    @Published var isAuthorized: Bool = false
    @Published var lastErrorMessage: String? = nil

    // MARK: - Authorization (READ-ONLY)

    /// Requests read authorization for BP/HR/SpO₂/ECG.
    func requestAuthorization(completion: ((Bool, Error?) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                self.isAuthorized = false
                self.lastErrorMessage = "Health data not available on this device."
            }
            completion?(false, nil)
            return
        }

        // Build the set to read (don’t mutate from within completion).
        var toRead = Set<HKObjectType>()

        if let q = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic) { toRead.insert(q) }
        if let q = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic){ toRead.insert(q) }
        if let q = HKObjectType.quantityType(forIdentifier: .heartRate)            { toRead.insert(q) }

        // SpO₂ (Blood Oxygen)
        if let q = HKObjectType.quantityType(forIdentifier: .oxygenSaturation)     { toRead.insert(q) }

        // ECG (Apple Watch, iOS 14+)
        if #available(iOS 14.0, *) {
            toRead.insert(HKObjectType.electrocardiogramType())
        }

        // Read-only: we are not writing any samples here.
        let toShare = Set<HKSampleType>()

        healthStore.requestAuthorization(toShare: toShare, read: toRead) { success, error in
            DispatchQueue.main.async {
                self.isAuthorized = success
                self.lastErrorMessage = error?.localizedDescription
                completion?(success, error)
            }
        }
    }

    // MARK: - Latest BP (correlation) + HR

    /// Fetch latest blood pressure correlation (systolic & diastolic), mmHg.
    func fetchLatestBloodPressure(completion: ((Double?, Double?, Error?) -> Void)? = nil) {
        guard let bpCorrelationType = HKObjectType.correlationType(forIdentifier: .bloodPressure) else {
            DispatchQueue.main.async {
                completion?(nil, nil,
                            NSError(domain: "HealthKitManager",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "BP correlation type unavailable"]))
            }
            return
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: bpCorrelationType, predicate: nil, limit: 1, sortDescriptors: [sort]) {
            [weak self] _, samplesOrNil, error in

            if let error = error {
                DispatchQueue.main.async {
                    self?.lastErrorMessage = error.localizedDescription
                    completion?(nil, nil, error)
                }
                return
            }

            guard
                let corr = (samplesOrNil as? [HKCorrelation])?.first,
                let sysType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
                let diaType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)
            else {
                DispatchQueue.main.async {
                    self?.systolic = nil
                    self?.diastolic = nil
                    completion?(nil, nil, nil)
                }
                return
            }

            let mmHg = HKUnit.millimeterOfMercury()
            let sys = (corr.objects(for: sysType).first as? HKQuantitySample)?.quantity.doubleValue(for: mmHg)
            let dia = (corr.objects(for: diaType).first as? HKQuantitySample)?.quantity.doubleValue(for: mmHg)

            DispatchQueue.main.async {
                self?.systolic = sys
                self?.diastolic = dia
                completion?(sys, dia, nil)
            }
        }

        healthStore.execute(query)
    }

    /// Fetch latest heart rate quantity sample, bpm.
    func fetchLatestHeartRate(completion: ((Double?, Error?) -> Void)? = nil) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            DispatchQueue.main.async {
                completion?(nil,
                            NSError(domain: "HealthKitManager",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Heart rate type unavailable"]))
            }
            return
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrType, predicate: nil, limit: 1, sortDescriptors: [sort]) {
            [weak self] _, samplesOrNil, error in

            if let error = error {
                DispatchQueue.main.async {
                    self?.lastErrorMessage = error.localizedDescription
                    completion?(nil, error)
                }
                return
            }

            guard let latest = (samplesOrNil as? [HKQuantitySample])?.first else {
                DispatchQueue.main.async {
                    self?.heartRate = nil
                    completion?(nil, nil)
                }
                return
            }

            let unit = HKUnit.count().unitDivided(by: .minute())
            let bpm = latest.quantity.doubleValue(for: unit)
            DispatchQueue.main.async {
                self?.heartRate = bpm
                completion?(bpm, nil)
            }
        }

        healthStore.execute(query)
    }

    /// Convenience to fetch both vitals.
    func fetchLatestVitals(completion: (() -> Void)? = nil) {
        let group = DispatchGroup()

        group.enter()
        fetchLatestBloodPressure { _, _, _ in group.leave() }

        group.enter()
        fetchLatestHeartRate { _, _ in group.leave() }

        group.notify(queue: .main) { completion?() }
    }

    // MARK: - Optional: write results (unchanged)

    func saveSessionResults(
        beforeSystolic: Double?, beforeDiastolic: Double?, beforeHR: Double?,
        afterSystolic: Double?,  afterDiastolic: Double?,  afterHR: Double?
    ) {
        var samplesToSave: [HKSample] = []
        let now = Date()

        let mmHg = HKUnit.millimeterOfMercury()
        let hrUnit = HKUnit.count().unitDivided(by: .minute())

        func makeBPCorrelation(sys: Double?, dia: Double?, date: Date) -> HKCorrelation? {
            guard
                let s = sys, let d = dia,
                let sysType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
                let diaType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic),
                let bpType  = HKObjectType.correlationType(forIdentifier: .bloodPressure)
            else { return nil }

            let sSample = HKQuantitySample(type: sysType, quantity: HKQuantity(unit: mmHg, doubleValue: s), start: date, end: date)
            let dSample = HKQuantitySample(type: diaType, quantity: HKQuantity(unit: mmHg, doubleValue: d), start: date, end: date)
            return HKCorrelation(type: bpType, start: date, end: date, objects: Set([sSample, dSample]))
        }

        func makeHRSample(_ val: Double?, date: Date) -> HKQuantitySample? {
            guard let v = val, let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
            return HKQuantitySample(type: hrType, quantity: HKQuantity(unit: hrUnit, doubleValue: v), start: date, end: date)
        }

        if let beforeBP = makeBPCorrelation(sys: beforeSystolic, dia: beforeDiastolic, date: now.addingTimeInterval(-60)) {
            samplesToSave.append(beforeBP)
        }
        if let afterBP  = makeBPCorrelation(sys: afterSystolic,  dia: afterDiastolic,  date: now) {
            samplesToSave.append(afterBP)
        }
        if let s = makeHRSample(beforeHR, date: now.addingTimeInterval(-50)) { samplesToSave.append(s) }
        if let s = makeHRSample(afterHR,  date: now)                          { samplesToSave.append(s) }

        guard !samplesToSave.isEmpty else { return }

        healthStore.save(samplesToSave) { _, error in
            DispatchQueue.main.async {
                if let error = error { self.lastErrorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Aliases for existing views

    var latestSystolic: Double?  { systolic }
    var latestDiastolic: Double? { diastolic }
    var latestHeartRate: Double? { heartRate }

    func refresh() { fetchLatestVitals() }
    func readLatestVitals(completion: (() -> Void)? = nil) {
        fetchLatestVitals(completion: completion)
    }
}
