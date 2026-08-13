//
//  ActivityView.swift
//  RoadSmoothness
//
//  Created by Jay Desai on 06/12/25.
//

import SwiftUI

struct ActivityView: View {
    @Bindable var manager: LocationAndMotionManager
    
    var body: some View {
        VStack {
            Text("Road Smoothness Tracker")
                .font(.headline)
                .padding(.bottom, 5)
            
//            Text("Activity: \(manager.currentActivityType)")
//                .font(.subheadline)
            Text("Speed: \(manager.currentSpeed, specifier: "%.1f") m/s")
                .font(.subheadline)
            Text("Bumpiness: \(manager.currentBumpiness, specifier: "%.4f")")
                .font(.subheadline)
                .foregroundColor(manager.currentBumpiness.bumpinessColor())
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .padding(.top, 50) // Adjust for notch/status bar
    }
}
