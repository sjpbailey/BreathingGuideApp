//
//  BPReading.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/4/25.
//

import Foundation

struct BPReading: Identifiable {
   let id = UUID()
   let systolic: Double
   let diastolic: Double
   let heartRate: Double
   let date: Date
}
