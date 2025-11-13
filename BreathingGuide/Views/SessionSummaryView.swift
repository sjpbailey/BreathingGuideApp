import SwiftUI

struct SessionSummaryView: View {
    @ObservedObject var healthKitManager: HealthKitManager

    // BEFORE values passed in from the session
    let bpBefore: (Double?, Double?)
    let hrBefore: Double?

    // Locally FROZEN copies so they never change
    @State private var bpBeforeFrozen: (Double?, Double?)? = nil
    @State private var hrBeforeFrozen: Double? = nil

    // AFTER values (set only when user taps Recheck)
    @State private var bpAfter: (Double?, Double?) = (nil, nil)
    @State private var hrAfter: Double? = nil

    @State private var isLoading = false
    @State private var showHealthSummary = false
    @Environment(\.dismiss) private var dismiss

    // Convenience: always use frozen-before if available
    private var effectiveBPBefore: (Double?, Double?) {
        bpBeforeFrozen ?? bpBefore
    }

    private var effectiveHRBefore: Double? {
        hrBeforeFrozen ?? hrBefore
    }

    var body: some View {
        NavigationStack {
            List {
                // Guidance + Recheck
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For the most accurate **After** values:")
                            .font(.headline)

                        Text("Open your **blood pressure app** on your cuff/device, take a fresh reading so it writes to Health, then tap **Recheck Now**.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            refreshAfter()
                        } label: {
                            HStack {
                                if isLoading { ProgressView().padding(.trailing, 6) }
                                Text(isLoading ? "Rechecking…" : "Recheck Now").bold()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }

                // BEFORE – always shows the original frozen values
                Section("Before") {
                    HStack {
                        Text("Blood Pressure")
                        Spacer()
                        Text(bpString(effectiveBPBefore)).bold()
                    }
                    HStack {
                        Text("Heart Rate")
                        Spacer()
                        Text(hrString(effectiveHRBefore)).bold()
                    }
                }

                // AFTER
                Section("After (from Health)") {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Reading latest values…")
                        }
                    } else {
                        HStack {
                            Text("Blood Pressure")
                            Spacer()
                            Text(bpString(bpAfter)).bold()
                        }
                        HStack {
                            Text("Heart Rate")
                            Spacer()
                            Text(hrString(hrAfter)).bold()
                        }
                    }
                }

                // CHANGE (Comparator) – uses the frozen BEFORE values
                Section("Change") {
                    HStack {
                        Text("BP Δ")
                        Spacer()
                        Text(bpDeltaString(before: effectiveBPBefore, after: bpAfter))
                            .bold()
                            .foregroundColor(
                                deltaColor(bpDeltaMagnitude(before: effectiveBPBefore, after: bpAfter))
                            )
                    }
                    HStack {
                        Text("HR Δ")
                        Spacer()
                        Text(hrDeltaString(before: effectiveHRBefore, after: hrAfter))
                            .bold()
                            .foregroundColor(
                                deltaColor(hrDeltaMagnitude(before: effectiveHRBefore, after: hrAfter))
                            )
                    }
                }

                // Weekly Summary button
                Section {
                    Button {
                        showHealthSummary = true
                    } label: {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                            Text("Weekly Summary")
                        }
                    }
                }
            }
            // 🔹 Renamed here
            .navigationTitle("Weekly Summary")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showHealthSummary) {
                HealthSummaryView(healthKitManager: healthKitManager)
            }
            .onAppear {
                // Freeze BEFORE values exactly once
                if bpBeforeFrozen == nil {
                    bpBeforeFrozen = bpBefore
                    hrBeforeFrozen = hrBefore
                }
            }
            // NOTE: no auto refreshAfter() here – only on button tap
        }
    }

    private func refreshAfter() {
        isLoading = true

        // Fetch latest BP
        healthKitManager.fetchLatestBloodPressure { s, d, _ in
            DispatchQueue.main.async {
                self.bpAfter = (s, d)
                self.isLoading = false
            }
        }

        // Fetch latest HR
        healthKitManager.fetchLatestHeartRate { hr, _ in
            DispatchQueue.main.async {
                self.hrAfter = hr
            }
        }
    }

    // MARK: - Formatters

    private func bpString(_ bp: (Double?, Double?)) -> String {
        let s = bp.0.flatMap { $0 > 0 ? Int($0.rounded()) : nil }
        let d = bp.1.flatMap { $0 > 0 ? Int($0.rounded()) : nil }
        switch (s, d) {
        case let (sv?, dv?): return "\(sv) / \(dv) mmHg"
        case (nil, nil):     return "-- / -- mmHg"
        case let (sv?, nil): return "\(sv) / -- mmHg"
        case let (nil, dv?): return "-- / \(dv) mmHg"
        }
    }

    private func hrString(_ v: Double?) -> String {
        guard let x = v, x > 0 else { return "-- bpm" }
        return "\(Int(x.rounded())) bpm"
    }

    // MARK: - Comparator helpers

    private func bpDeltaString(before: (Double?, Double?), after: (Double?, Double?)) -> String {
        guard
            let bs = before.0, let bd = before.1,
            let asv = after.0,  let adv = after.1
        else { return "—" }

        let dS = Int((asv - bs).rounded())
        let dD = Int((adv - bd).rounded())
        let arrowS = arrow(for: dS)
        let arrowD = arrow(for: dD)
        return "\(arrowS)\(abs(dS)) / \(arrowD)\(abs(dD)) mmHg"
    }

    private func hrDeltaString(before: Double?, after: Double?) -> String {
        guard let b = before, let a = after else { return "—" }
        let d = Int((a - b).rounded())
        let arrowHR = arrow(for: d)
        return "\(arrowHR)\(abs(d)) bpm"
    }

    private func bpDeltaMagnitude(before: (Double?, Double?), after: (Double?, Double?)) -> Double? {
        guard
            let bs = before.0,  let _ = before.1,
            let asv = after.0,  let _ = after.1
        else { return nil }
        // Use systolic delta magnitude to color (simple, readable)
        return abs(asv - bs)
    }

    private func hrDeltaMagnitude(before: Double?, after: Double?) -> Double? {
        guard let b = before, let a = after else { return nil }
        return abs(a - b)
    }

    private func arrow(for delta: Int) -> String {
        if delta > 0 { return "↑" }
        if delta < 0 { return "↓" }
        return "±"
    }

    private func deltaColor(_ magnitude: Double?) -> Color {
        // Neutral for no data; otherwise subtle coloring
        guard let mag = magnitude else { return .secondary }
        if mag >= 10 { return .red }       // larger change
        if mag >= 5  { return .orange }    // moderate change
        return .green                      // small/beneficial change
    }
}
