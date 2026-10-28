//
//  BumpinessGaugeView.swift
//  Khadda
//

import SwiftUI

/// A sleek linear progress gauge bar with smooth color thresholds to categorize road bumpiness.
struct BumpinessGaugeView: View {
    let bumpinessScore: Double
    var maxScore: Double = 0.06
    var isCompact: Bool = false
    
    var category: BumpinessCategory {
        BumpinessCategory.category(for: bumpinessScore)
    }
    
    /// Calculated progress value normalized between 0.0 and 1.0.
    private var normalizedProgress: Double {
        min(max(bumpinessScore / maxScore, 0.0), 1.0)
    }
    
    var body: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            // Header section with Category badge and score
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: category.iconName)
                        .foregroundColor(category.color)
                        .font(isCompact ? .caption : .subheadline)
                    
                    Text(category.rawValue)
                        .font(isCompact ? .subheadline : .headline)
                        .fontWeight(.bold)
                        .foregroundColor(category.color)
                }
                
                Spacer()
                
                Text(String(format: "%.4f", bumpinessScore))
                    .font(isCompact ? .caption : .subheadline)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            // Linear Gauge Bar
            GeometryReader { geometry in
                let barWidth = geometry.size.width
                let markerOffset = CGFloat(normalizedProgress) * barWidth
                
                ZStack(alignment: .leading) {
                    // Multi-color gradient track representing smooth-to-rough thresholds
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .green,
                            .yellow,
                            .orange,
                            .red,
                            Color(red: 0.5, green: 0, blue: 0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: isCompact ? 8 : 12)
                    .clipShape(Capsule())
                    
                    // Moving cursor pin indicator
                    Circle()
                        .fill(Color.white)
                        .frame(width: isCompact ? 14 : 18, height: isCompact ? 14 : 18)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                        .overlay(
                            Circle()
                                .stroke(category.color, lineWidth: isCompact ? 2 : 3)
                        )
                        .offset(x: min(max(markerOffset - (isCompact ? 7 : 9), 0), barWidth - (isCompact ? 14 : 18)))
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: bumpinessScore)
                }
            }
            .frame(height: isCompact ? 14 : 18)
            
            // Labels for scale thresholds (Full view only)
            if !isCompact {
                HStack {
                    Text("Smooth")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Moderate")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Severe")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview("Standard View") {
    VStack(spacing: 20) {
        BumpinessGaugeView(bumpinessScore: 0.003)
        BumpinessGaugeView(bumpinessScore: 0.012)
        BumpinessGaugeView(bumpinessScore: 0.025)
        BumpinessGaugeView(bumpinessScore: 0.042)
        BumpinessGaugeView(bumpinessScore: 0.058)
    }
    .padding()
}

#Preview("Compact View") {
    VStack(spacing: 20) {
        BumpinessGaugeView(bumpinessScore: 0.012, isCompact: true)
        BumpinessGaugeView(bumpinessScore: 0.042, isCompact: true)
    }
    .padding()
}
