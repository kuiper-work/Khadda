//
//  BumpinessEngine.swift
//  Khadda
//

import Foundation

/// Sliding window variance engine that tracks motion stability over recent acceleration samples.
/// Uses a native Swift fixed-size circular buffer for O(1) sample insertion and eviction,
/// combined with an online sliding-window update for O(1) variance calculation.
struct BumpinessEngine: Sendable {
    /// Total number of samples required to form a full sliding window.
    private let slidingWindowSize: Int

    /// Pre-allocated circular buffer that stores the most recent motion magnitude samples.
    private var circularSampleBuffer: [Double]

    /// The index in `circularSampleBuffer` where the next incoming sample will be written,
    /// overwriting the oldest sample once the buffer is full.
    private var currentBufferWriteIndex: Int = 0

    /// Number of valid samples received so far, up to `slidingWindowSize`.
    private var recordedSampleCount: Int = 0

    /// Running arithmetic mean of the samples currently in the sliding window.
    private var runningMean: Double = 0.0

    /// Running sum of squared differences from the mean: ∑(x - μ)².
    /// Used to calculate sample/population variance in O(1) time without re-scanning the buffer.
    private var runningSumOfSquaredDeviations: Double = 0.0

    /// Indicates whether the sliding window has collected enough samples to compute valid variance.
    var isWindowFull: Bool {
        recordedSampleCount >= slidingWindowSize
    }

    /// Creates an engine with the specified sliding window size.
    /// - Parameter windowSize: Number of samples in the sliding window (must be >= 2).
    init(windowSize: Int = 50) {
        let normalizedSize = max(windowSize, 2)
        self.slidingWindowSize = normalizedSize
        self.circularSampleBuffer = [Double](repeating: 0.0, count: normalizedSize)
    }

    /// Ingests a 3-axis accelerometer sample and returns the current variance.
    /// - Parameters:
    ///   - xAcceleration: Acceleration along X axis (in g).
    ///   - yAcceleration: Acceleration along Y axis (in g).
    ///   - zAcceleration: Acceleration along Z axis (in g).
    /// - Returns: Current sliding window variance (0.0 if window is not yet full).
    mutating func addSample(x xAcceleration: Double, y yAcceleration: Double, z zAcceleration: Double) -> Double {
        let totalMotionMagnitude = (xAcceleration * xAcceleration +
                                    yAcceleration * yAcceleration +
                                    zAcceleration * zAcceleration).squareRoot()
        return addSample(magnitude: totalMotionMagnitude)
    }

    /// Ingests a pre-computed scalar motion magnitude and returns the current sliding window variance.
    /// - Parameter motionMagnitude: Scalar motion metric.
    /// - Returns: Current sliding window variance (0.0 if window is not yet full).
    @discardableResult
    mutating func addSample(magnitude motionMagnitude: Double) -> Double {
        if !isWindowFull {
            // Window is filling up: insert into pre-allocated circular buffer in O(1)
            circularSampleBuffer[currentBufferWriteIndex] = motionMagnitude
            currentBufferWriteIndex = (currentBufferWriteIndex + 1) % slidingWindowSize
            recordedSampleCount += 1

            // Welford's online single-pass variance update
            let currentWindowCount = Double(recordedSampleCount)
            let differenceFromPreviousMean = motionMagnitude - runningMean
            runningMean += differenceFromPreviousMean / currentWindowCount
            let differenceFromUpdatedMean = motionMagnitude - runningMean
            runningSumOfSquaredDeviations += differenceFromPreviousMean * differenceFromUpdatedMean
        } else {
            // Window is full: retrieve and overwrite the oldest sample at current write index in O(1)
            let evictedOldestSample = circularSampleBuffer[currentBufferWriteIndex]
            circularSampleBuffer[currentBufferWriteIndex] = motionMagnitude
            currentBufferWriteIndex = (currentBufferWriteIndex + 1) % slidingWindowSize

            // Sliding Welford update: downdate the evicted sample and update with the new sample in O(1)
            let sampleDifference = motionMagnitude - evictedOldestSample
            let previousMean = runningMean
            let totalWindowCapacity = Double(slidingWindowSize)

            runningMean += sampleDifference / totalWindowCapacity
            runningSumOfSquaredDeviations += sampleDifference * (
                (motionMagnitude - runningMean) + (evictedOldestSample - previousMean)
            )
        }

        guard isWindowFull else {
            return 0.0
        }

        let slidingWindowVariance = runningSumOfSquaredDeviations / Double(slidingWindowSize)
        return max(0.0, slidingWindowVariance)
    }

    /// Resets all internal samples, indices, and tracking statistics to their initial empty states.
    mutating func reset() {
        circularSampleBuffer = [Double](repeating: 0.0, count: slidingWindowSize)
        currentBufferWriteIndex = 0
        recordedSampleCount = 0
        runningMean = 0.0
        runningSumOfSquaredDeviations = 0.0
    }
}
