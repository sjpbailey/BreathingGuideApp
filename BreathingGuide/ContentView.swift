//
//  ContentView.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/4/25.
//

//
//  ContentView.swift
//  BreathingGuide
//
//  Wires up HealthKitManager and passes it into MeasureVitalsView.
//  No HealthKit calls here — MeasureVitalsView handles Refresh/Authorize.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()

    var body: some View {
        NavigationStack {
            MeasureVitalsView(healthKitManager: healthKitManager)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            // If your SessionSummaryView uses a BLEManager via .environmentObject,
            // you can uncomment the next line for preview safety:
            // .environmentObject(BLEManager())
    }
}

