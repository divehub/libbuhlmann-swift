import Foundation

enum DecoUtils {
    static let depthTolerance = 0.01
    static let gasEpsilon = 0.001

    static func depthsEqual(_ d1: Double, _ d2: Double) -> Bool {
        abs(d1 - d2) < depthTolerance
    }

    static func nextStopDepth(from d: Double, stopIncrement: Double, lastStopDepth: Double) -> Double {
        var next = floor(d / stopIncrement) * stopIncrement
        // If we're already at a stop depth, go to the next shallower one
        if depthsEqual(next, d) {
            next -= stopIncrement
        }
        // Enforce last stop depth
        if next > depthTolerance && next < lastStopDepth - depthTolerance {
            next = d > lastStopDepth + depthTolerance ? lastStopDepth : 0
        }
        return max(0, next)
    }
}
