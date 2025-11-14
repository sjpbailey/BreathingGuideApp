//
//  MeasureVitalsView.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/4/25.

import SwiftUI

struct MeasureVitalsView: View {
    @ObservedObject var healthKitManager: HealthKitManager

    // UI state
    @State private var minutes: Double = 5
    @State private var isRefreshing = false
    @State private var showSession = false
    @State private var didRefreshThisLaunch = false   // true ONLY when user taps Refresh

    // Frozen “before” values captured right when the user taps Start
    @State private var startSys: Double?
    @State private var startDia: Double?
    @State private var startHR:  Double?

    // Help sheet
    @State private var showHowItWorks = false

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Breathing Guide")
                    .font(.largeTitle.bold())
                Spacer()
                // Help button opens your detailed HowItWorksView
                Button {
                    showHowItWorks = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .imageScale(.large)
                        .accessibilityLabel("How the app works")
                }
            }

            // Latest values currently in memory (shown even if stale or missing)
            VStack(spacing: 10) {
                line(title: "Systolic",  value: bpPartString(healthKitManager.latestSystolic))
                line(title: "Diastolic", value: bpPartString(healthKitManager.latestDiastolic))
                line(title: "Heart Rate",value: hrString(healthKitManager.latestHeartRate))
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // Duration slider (minutes)
            VStack(spacing: 8) {
                Text("Session Duration: \(Int(minutes)) minute\(Int(minutes) == 1 ? "" : "s")")
                    .font(.headline)
                Slider(value: $minutes, in: 1...10, step: 1)
                    .tint(.blue)
            }
            .padding(.horizontal)

            // Controls
            VStack(spacing: 12) {
                Button {
                    refreshVitals()      // <-- Only place we read HealthKit
                } label: {
                    HStack {
                        if isRefreshing { ProgressView().progressViewStyle(.circular) }
                        Text(isRefreshing ? "Refreshing…" : "Refresh Vitals").bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isRefreshing ? Color.gray : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isRefreshing)

                // ✅ Always allow starting the breathing exercise
                Button {
                    // Freeze whatever is currently in memory (fresh, stale, or nil)
                    startSys = healthKitManager.latestSystolic
                    startDia = healthKitManager.latestDiastolic
                    startHR  = healthKitManager.latestHeartRate
                    showSession = true
                } label: {
                    Text("Start Breathing Exercise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                // ⬆️ No .disabled() here anymore
            }
            .padding(.horizontal)

            Spacer()

            // Clear guidance: BP is optional, HR is optional.
            Text("Tip: For the most complete picture, take a fresh BP in your cuff app and a heart rate reading, then tap **Refresh Vitals** before starting. If you don’t track BP, you can still use the breathing exercise with heart rate or no vitals at all.")
                .font(.footnote) // we can bump this to .body later if you want it bigger
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        // No auto-read on appear—just request authorization so Refresh can work.
        .onAppear {
            healthKitManager.requestAuthorization { _,_  in }
        }
        .sheet(isPresented: $showSession) {
            BreathingSessionView(
                healthKitManager: healthKitManager,
                totalSessionSeconds: Int(minutes) * 60,
                // ✅ Use the frozen values if we captured them, otherwise whatever is in memory (can be nil)
                beforeSystolic: startSys ?? healthKitManager.latestSystolic,
                beforeDiastolic: startDia ?? healthKitManager.latestDiastolic,
                beforeHeartRate: startHR ?? healthKitManager.latestHeartRate,
                staleOnLaunch: !didRefreshThisLaunch
            )
        }
        .sheet(isPresented: $showHowItWorks) {
            HowItWorksView()
        }
    }

    // MARK: - Helpers

    // We keep this for now in case we want logic later, but it always returns true
    private var canStart: Bool {
        true
    }

    private func refreshVitals() {
        isRefreshing = true
        healthKitManager.requestAuthorization { success, _ in
            guard success else {
                DispatchQueue.main.async { self.isRefreshing = false }
                return
            }
            healthKitManager.readLatestVitals {
                DispatchQueue.main.async {
                    self.isRefreshing = false
                    self.didRefreshThisLaunch = true   // user explicitly refreshed

                    // Capture the “before” readings immediately after refresh
                    self.startSys = healthKitManager.latestSystolic
                    self.startDia = healthKitManager.latestDiastolic
                    self.startHR  = healthKitManager.latestHeartRate
                }
            }
        }
    }

    private func line(title: String, value: String) -> some View {
        HStack {
            Text(title + ":")
            Spacer()
            Text(value).bold()
        }
        .font(.title2)
    }

    private func bpPartString(_ v: Double?) -> String {
        guard let x = v, x > 0 else { return "--" }
        return "\(Int(x.rounded()))"
    }

    private func hrString(_ v: Double?) -> String {
        guard let x = v, x > 0 else { return "-- bpm" }
        return "\(Int(x.rounded())) bpm"
    }
}
