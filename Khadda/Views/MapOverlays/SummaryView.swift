//
//  SummaryView.swift
//  RoadSmoothness
//
//  Created by Jay Desai on 06/12/25.
//
import SwiftUI

struct SummaryView: View {
    @Bindable var manager: LocationAndMotionManager
    
    var body: some View {
        if !manager.isTracking {
            VStack {
                Text("Ride Summary")
                    .font(.headline)
                    .padding(.bottom, 5)
                Text("Total Distance: \(manager.totalDistance / 1000, specifier: "%.2f") km")
                    .font(.subheadline)
                Text("Average Bumpiness: \(manager.averageBumpiness, specifier: "%.4f")")
                    .font(.subheadline)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .padding(.bottom, 100) // Adjust to be above the button
        }
    }
}
