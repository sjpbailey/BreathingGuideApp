//
//  BreathingGuideApp.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/4/25.
//

import SwiftUI

@main
struct BreathingGuideApp: App {
   @StateObject var healthKitManager = HealthKitManager()
   @StateObject var bleManager = BLEManager()

   var body: some Scene {
       WindowGroup {
           ContentView()
               .environmentObject(healthKitManager)
               .environmentObject(bleManager)
       }
   }
}
