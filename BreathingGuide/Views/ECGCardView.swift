//
//  ECGCardView.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/11/25.
//

import SwiftUI

struct ECGCardView: View {
    let classification: String
    let averageHR: Double?
    let date: Date
    let samples: [Double]   // voltage samples

    @State private var zoom: CGFloat = 1.0     // 1× to 4× horizontal zoom
    @State private var dragOffset: CGFloat = 0 // horizontal pan

    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // MARK: - Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ECG")
                        .font(.headline)

                    Text(classification)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let avg = averageHR {
                    Text("\(Int(avg)) bpm")
                        .font(.headline)
                        .foregroundColor(.pink)
                }
            }

            // MARK: - Waveform + Background Grid + Interaction
            VStack(spacing: 8) {
                Text("Waveform (10s snapshot)")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                // Zoom + Pan area
                ScrollView(.horizontal) {
                    ECGWaveformShape(samples: samples)
                        .stroke(Color.blue.opacity(0.9), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                        .frame(
                            width: max(350, CGFloat(samples.count) / 3 * zoom),
                            height: 140
                        )
                        .background(
                            ECGGrid()
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.8)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.vertical, 4)
                }
                .frame(height: 150)

                // Zoom Slider
                HStack {
                    Text("Zoom")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Slider(
                        value: Binding(
                            get: { Double(zoom) },
                            set: { zoom = max(0.5, min(CGFloat($0), 4.0)) }
                        ),
                        in: 0.5...4.0
                    )
                }
            }

            // MARK: - Footer Date
            Text(formattedDate)
                .font(.footnote)
                .foregroundColor(.secondary)

        }
        .padding()
        .background(Color(.systemBackground).opacity(0.95))
        .cornerRadius(16)
        .shadow(radius: 2, y: 1)
    }
}

//
//  ECG WAVEFORM SHAPE
//
struct ECGWaveformShape: Shape {
    let samples: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count > 2 else { return path }

        // Normalize samples into [-1, 1]
        let minVal = samples.min() ?? 0
        let maxVal = samples.max() ?? 0
        let range = max(maxVal - minVal, 0.0001)
        let normalized = samples.map { (($0 - minVal) / range) * 2 - 1 }

        let midY = rect.midY
        let height = rect.height / 2
        let stepX = rect.width / CGFloat(max(samples.count - 1, 1))

        path.move(to: CGPoint(x: 0, y: midY - normalized[0] * height))

        for i in 1..<samples.count {
            let x = CGFloat(i) * stepX
            let y = midY - normalized[i] * height
            path.addLine(to: CGPoint(x: x, y: y))
        }

        return path
    }
}

//
//  GRID BACKGROUND (ECG-style)
//
struct ECGGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()

        let smallStep: CGFloat = 8   // tiny squares like real ECG paper
        let bigStep:   CGFloat = 40  // bold every 5 squares

        // Vertical lines
        for x in stride(from: 0, through: rect.width, by: smallStep) {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
        }

        // Horizontal lines
        for y in stride(from: 0, through: rect.height, by: smallStep) {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: rect.width, y: y))
        }

        // Bold grid (every 5 squares)
        for x in stride(from: 0, through: rect.width, by: bigStep) {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
        }

        for y in stride(from: 0, through: rect.height, by: bigStep) {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: rect.width, y: y))
        }

        return p
    }
}
