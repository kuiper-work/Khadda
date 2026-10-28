//
//  SummaryView.swift
//  RoadSmoothness
//
//  Created by Jay Desai on 06/12/25.
//

import SwiftUI

struct SummaryView: View {
    var totalDistance: Double
    var avgBumpiness: Double
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Ride Summary")
                .font(.headline)
                .padding(.bottom, 2)
            
            Text("Total Distance: \(totalDistance / 1000, specifier: "%.2f") km")
                .font(.subheadline)
            
            Text("Average Bumpiness: \(avgBumpiness, specifier: "%.4f")")
                .font(.subheadline)
                .foregroundColor(avgBumpiness.bumpinessColor())
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }
}

#Preview {
    SummaryView(totalDistance: 5400, avgBumpiness: 0.018)
}
