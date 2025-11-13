//
//  HealthSummaryView.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/8/25.
//

import SwiftUI
import Charts

struct HealthSummaryView: View {
    @ObservedObject var healthKitManager: HealthKitManager

    @State private var bpItems: [(date: Date, systolic: Double, diastolic: Double)] = []
    @State private var hrDays: [HealthKitManager.HRDaySummary] = []
    @State private var spo2Value: Double?
    @State private var spo2Date: Date?
    @State private var ecgClass: String?
    @State private var ecgDate: Date?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Soft background behind everything
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color.blue.opacity(0.12),
                        Color.indigo.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {

                        // MARK: - HEADER
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Weekly Snapshot")
                                .font(.title2.bold())
                            Text("A quick look at your recent blood pressure, heart rate, and oxygen.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        
                        // MARK: - TREND CHART CARD
                        if !bpItems.isEmpty || !hrDays.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Label("Trends (Last 7 Days)", systemImage: "chart.line.uptrend.xyaxis")
                                        .font(.headline)
                                    Spacer()
                                }

                                // --- BP Chart ---
                                if !bpItems.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Blood Pressure")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.primary)

                                        Chart {
                                            ForEach(bpItems, id: \.date) { it in
                                                LineMark(
                                                    x: .value("Day", it.date),
                                                    y: .value("Systolic", it.systolic)
                                                )
                                                .interpolationMethod(.catmullRom)

                                                LineMark(
                                                    x: .value("Day", it.date),
                                                    y: .value("Diastolic", it.diastolic)
                                                )
                                                .interpolationMethod(.catmullRom)
                                            }
                                        }
                                        .frame(height: 180)
                                        .chartXAxis {
                                            AxisMarks(values: .stride(by: .day)) { _ in
                                                AxisGridLine()
                                                AxisTick()
                                            }
                                        }
                                        .chartYAxis {
                                            AxisMarks()
                                        }
                                        .chartScrollableAxes(.horizontal)
                                        .chartXVisibleDomain(length: 4 * 24 * 60 * 60)

                                        Text("Latest reading saved in Health for each of the last 7 days.")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                // --- HR Chart ---
                                if !hrDays.isEmpty {
                                    Divider()
                                        .padding(.vertical, 4)

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Heart Rate (Min • Avg • Max)")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.primary)

                                        Chart {
                                            ForEach(hrDays) { d in
                                                BarMark(
                                                    x: .value("Day", d.date),
                                                    yStart: .value("Min", d.min),
                                                    yEnd: .value("Max", d.max)
                                                )
                                                LineMark(
                                                    x: .value("Day", d.date),
                                                    y: .value("Avg", d.avg)
                                                )
                                            }
                                        }
                                        .frame(height: 180)
                                        .chartXAxis {
                                            AxisMarks(values: .stride(by: .day)) { _ in
                                                AxisGridLine()
                                                AxisTick()
                                            }
                                        }
                                        .chartYAxis {
                                            AxisMarks()
                                        }
                                        .chartScrollableAxes(.horizontal)
                                        .chartXVisibleDomain(length: 4 * 24 * 60 * 60)

                                        Text("Based on all heart rate samples recorded each day.")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(.thinMaterial)
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                            .padding(.horizontal)
                        }

                        // MARK: - BP LIST CARD
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "heart.text.square")
                                    .foregroundColor(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Blood Pressure")
                                        .font(.headline)
                                    Text("Latest reading from each day")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            if bpItems.isEmpty {
                                Text("No recent blood pressure data found.")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(bpItems.indices, id: \.self) { i in
                                    let it = bpItems[i]
                                    HStack {
                                        Text(shortDate(it.date))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(it.systolic)) / \(Int(it.diastolic)) mmHg")
                                            .font(.body.weight(.semibold))
                                    }
                                    .padding(.vertical, 4)

                                    if i != bpItems.indices.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground).opacity(0.98))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                        .padding(.horizontal)

                        // MARK: - HR LIST CARD
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform.path.ecg")
                                    .foregroundColor(.pink)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Heart Rate")
                                        .font(.headline)
                                    Text("Daily min • avg • max")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            if hrDays.isEmpty {
                                Text("No recent heart rate samples found.")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(hrDays) { d in
                                    HStack {
                                        Text(shortDate(d.date))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("min \(Int(d.min)) • avg \(Int(d.avg)) • max \(Int(d.max)) bpm")
                                            .font(.body.weight(.semibold))
                                    }
                                    .padding(.vertical, 4)

                                    if d.id != hrDays.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground).opacity(0.98))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                        .padding(.horizontal)

                        // MARK: - SPO2 CARD
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "lungs.fill")
                                    .foregroundColor(.teal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Blood Oxygen (SpO₂)")
                                        .font(.headline)
                                    Text("Most recent value from Health")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            if let v = spo2Value, let dt = spo2Date {
                                HStack {
                                    Text("Latest value")
                                    Spacer()
                                    Text(String(format: "%.0f%%", v))
                                        .font(.title3.bold())
                                }

                                Text("Measured: \(longDate(dt))")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No SpO₂ samples found or not authorized.")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground).opacity(0.98))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                        .padding(.horizontal)

                        // MARK: - ECG WAVEFORM CARD (kept, but simple)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform")
                                    .foregroundColor(.purple)
                                Text("ECG Waveform")
                                    .font(.headline)
                                Spacer()
                            }

                            ECGSectionWrapper(healthKitManager: healthKitManager)
                                .font(.subheadline)
                        }
                        .padding()
                        .background(Color(.systemBackground).opacity(0.98))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                        .padding(.horizontal)

                        // MARK: - ECG CLASSIFICATION
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "heart.text.square.fill")
                                    .foregroundColor(.red)
                                Text("ECG Classification")
                                    .font(.headline)
                                Spacer()
                            }

                            if let c = ecgClass, let dt = ecgDate {
                                HStack {
                                    Text("Latest classification")
                                    Spacer()
                                    Text(c)
                                        .bold()
                                }
                                Text("Recorded: \(longDate(dt))")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No ECG classification available or not authorized.")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground).opacity(0.98))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                        .padding(.horizontal)

                        Spacer(minLength: 20)
                    }
                    .padding(.top, 8)
                }
            }
            // 🔹 Renamed here
            .navigationTitle("Weekly Summary")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { reloadAll() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { reloadAll() }
        }
    }

    private func reloadAll() {
        healthKitManager.fetchLast7DaysBloodPressure { self.bpItems = $0 }
        healthKitManager.fetchLast7DaysHeartRateSummary { self.hrDays = $0 }
        healthKitManager.fetchLatestSpO2 { val, dt in
            self.spo2Value = val
            self.spo2Date = dt
        }
        healthKitManager.fetchLatestECG { cls, dt in
            self.ecgClass = cls
            self.ecgDate = dt
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        return f.string(from: d)
    }

    private func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

// Minimal wrapper that fetches once and shows the ECGCardView if available.
private struct ECGSectionWrapper: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @State private var snapshot: HealthKitManager.ECGSnapshot? = nil
    @State private var loaded = false

    var body: some View {
        Group {
            if let s = snapshot {
                ECGCardView(
                    classification: s.classification,
                    averageHR: s.averageHeartRate,
                    date: s.date,
                    samples: s.samples
                )
            } else if loaded {
                Text("No recent ECG waveform available.")
                    .foregroundColor(.secondary)
            } else {
                Text("Loading ECG data…")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            healthKitManager.fetchLatestECGSnapshot(seconds: 10, maxPoints: 1200) { snap in
                self.snapshot = snap
            }
        }
    }
}
