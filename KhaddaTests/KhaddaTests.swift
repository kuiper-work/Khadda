//
//  KhaddaTests.swift
//  KhaddaTests
//

import Testing
import SwiftUI
@testable import Khadda

struct KhaddaTests {

    // MARK: - Bumpiness Category Threshold Tests
    @Test("Categorizes score below 0.005 as Very Smooth")
    func testVerySmoothCategory() {
        let score = 0.002
        let category = BumpinessCategory.category(for: score)
        #expect(category == .verySmooth)
        #expect(score.bumpinessColor() == Color.green)
    }

    @Test("Categorizes score between 0.005 and 0.015 as Smooth")
    func testSmoothCategory() {
        let score = 0.010
        let category = BumpinessCategory.category(for: score)
        #expect(category == .smooth)
        #expect(score.bumpinessColor() == Color.yellow)
    }

    @Test("Categorizes score between 0.015 and 0.03 as Bumpy")
    func testBumpyCategory() {
        let score = 0.022
        let category = BumpinessCategory.category(for: score)
        #expect(category == .bumpy)
        #expect(score.bumpinessColor() == Color.orange)
    }

    @Test("Categorizes score between 0.03 and 0.05 as Very Bumpy")
    func testVeryBumpyCategory() {
        let score = 0.041
        let category = BumpinessCategory.category(for: score)
        #expect(category == .veryBumpy)
        #expect(score.bumpinessColor() == Color.red)
    }

    @Test("Categorizes score of 0.05 or higher as Severe Potholes")
    func testSevereCategory() {
        let score = 0.065
        let category = BumpinessCategory.category(for: score)
        #expect(category == .severe)
        #expect(score.bumpinessColor() == Color(red: 0.5, green: 0, blue: 0))
    }

    // MARK: - Edge Boundaries Tests
    @Test("Test category boundary exact thresholds")
    func testCategoryBoundaries() {
        #expect(BumpinessCategory.category(for: 0.000) == .verySmooth)
        #expect(BumpinessCategory.category(for: 0.00499) == .verySmooth)
        #expect(BumpinessCategory.category(for: 0.005) == .smooth)
        #expect(BumpinessCategory.category(for: 0.01499) == .smooth)
        #expect(BumpinessCategory.category(for: 0.015) == .bumpy)
        #expect(BumpinessCategory.category(for: 0.02999) == .bumpy)
        #expect(BumpinessCategory.category(for: 0.03) == .veryBumpy)
        #expect(BumpinessCategory.category(for: 0.04999) == .veryBumpy)
        #expect(BumpinessCategory.category(for: 0.05) == .severe)
        #expect(BumpinessCategory.category(for: 0.10) == .severe)
    }

    // MARK: - Category Metadata Tests
    @Test("Validates category display properties")
    func testCategoryMetadata() {
        for category in BumpinessCategory.allCases {
            #expect(!category.rawValue.isEmpty)
            #expect(!category.iconName.isEmpty)
            #expect(!category.statusDescription.isEmpty)
            #expect(category.id == category.rawValue)
        }
    }

    // MARK: - Status Dot View Tests
    @Test("Validates StatusDotView active and inactive state")
    func testStatusDotView() {
        let activeDotView = StatusDotView(isActive: true)
        #expect(activeDotView.isActive == true)
        
        let inactiveDotView = StatusDotView(isActive: false)
        #expect(inactiveDotView.isActive == false)
    }

    // MARK: - BumpinessEngine Tests
    @Test("BumpinessEngine produces zero variance for constant inputs")
    func testEngineConstantInputs() {
        var engine = BumpinessEngine(windowSize: 10)
        var lastScore = 0.0
        for _ in 0..<10 {
            lastScore = engine.addSample(magnitude: 1.0)
        }
        #expect(abs(lastScore) < 0.000001)
    }

    @Test("BumpinessEngine calculates exact variance for known sample set")
    func testEngineKnownVariance() {
        // Sample dataset: [2, 4, 4, 4, 5, 5, 7, 9]
        // Mean = 40 / 8 = 5.0
        // Sum of squared deviations: 9 + 1 + 1 + 1 + 0 + 0 + 4 + 16 = 32
        // Population Variance = 32 / 8 = 4.0
        let samples = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
        var engine = BumpinessEngine(windowSize: samples.count)
        var calculatedVariance = 0.0
        for sample in samples {
            calculatedVariance = engine.addSample(magnitude: sample)
        }
        #expect(abs(calculatedVariance - 4.0) < 0.0001)
    }

    @Test("BumpinessEngine evicts oldest sample when sliding window is full")
    func testEngineSlidingWindowEviction() {
        var engine = BumpinessEngine(windowSize: 4)
        // Add 4 constant samples: [2, 2, 2, 2] -> variance 0.0
        for _ in 0..<4 {
            _ = engine.addSample(magnitude: 2.0)
        }
        // Add a fifth sample: buffer becomes [2, 2, 2, 6] -> mean = 3.0
        // Variance: ( (2-3)^2 * 3 + (6-3)^2 ) / 4 = (3 + 9) / 4 = 3.0
        let variance = engine.addSample(magnitude: 6.0)
        #expect(abs(variance - 3.0) < 0.0001)
    }

    @Test("BumpinessEngine accurately computes vector magnitude from 3 axes")
    func testEngineVectorMagnitude() {
        var engine = BumpinessEngine(windowSize: 2)
        _ = engine.addSample(x: 3.0, y: 4.0, z: 0.0) // magnitude = 5.0
        let variance = engine.addSample(x: 0.0, y: 0.0, z: 5.0) // magnitude = 5.0
        // Both magnitudes are 5.0, so variance must be 0.0
        #expect(abs(variance) < 0.000001)
    }
}
