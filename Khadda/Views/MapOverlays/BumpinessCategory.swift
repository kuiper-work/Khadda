//
//  BumpinessCategory.swift
//  Khadda
//

import SwiftUI

/// Categorizes road bumpiness levels based on acceleration variance scores.
enum BumpinessCategory: String, CaseIterable, Codable, Identifiable {
    case verySmooth = "Very Smooth"
    case smooth = "Smooth"
    case bumpy = "Bumpy"
    case veryBumpy = "Very Bumpy"
    case severe = "Severe Potholes"
    
    var id: String { rawValue }
    
    /// Determines the bumpiness category for a given score.
    static func category(for score: Double) -> BumpinessCategory {
        if score < 0.005 {
            return .verySmooth
        } else if score < 0.015 {
            return .smooth
        } else if score < 0.03 {
            return .bumpy
        } else if score < 0.05 {
            return .veryBumpy
        } else {
            return .severe
        }
    }
    
    /// Associated theme color for the category.
    var color: Color {
        switch self {
        case .verySmooth:
            return .green
        case .smooth:
            return .yellow
        case .bumpy:
            return .orange
        case .veryBumpy:
            return .red
        case .severe:
            return Color(red: 0.5, green: 0, blue: 0)
        }
    }
    
    /// SF Symbol icon associated with the category.
    var iconName: String {
        switch self {
        case .verySmooth:
            return "checkmark.circle.fill"
        case .smooth:
            return "shield.checkerboard"
        case .bumpy:
            return "exclamationmark.triangle.fill"
        case .veryBumpy:
            return "xmark.octagon.fill"
        case .severe:
            return "hazardmark.fill"
        }
    }
    
    /// Brief description of the category status.
    var statusDescription: String {
        switch self {
        case .verySmooth:
            return "Excellent condition"
        case .smooth:
            return "Good condition"
        case .bumpy:
            return "Moderate roughness"
        case .veryBumpy:
            return "Poor road surface"
        case .severe:
            return "Severe potholes"
        }
    }
}
