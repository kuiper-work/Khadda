//
//  ActivityView.swift
//  RoadSmoothness
//

import SwiftUI

struct ActivityView: View {
    var currentSpeed: Double
    var currentBumpiness: Double
    var currentActivityType: String
    
    var isDriving: Bool {
        currentActivityType == "Driving"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatusDotView(isActive: isDriving)
                
                Image(systemName: "car.side.fill")
                    .font(.headline)
                    .foregroundColor(isDriving ? .primary : .gray)
            }
            .padding(.bottom, 2)
            
            Text("Activity: \(currentActivityType)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Speed: \(currentSpeed * 3.6, specifier: "%.1f") km/h")
                .font(.subheadline)
            
            Text("Bumpiness: \(currentBumpiness, specifier: "%.4f")")
                .font(.subheadline)
                .foregroundColor(currentBumpiness.bumpinessColor())
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }
}

#Preview {
    ActivityView(currentSpeed: 12.5, currentBumpiness: 0.024, currentActivityType: "Driving")
}
