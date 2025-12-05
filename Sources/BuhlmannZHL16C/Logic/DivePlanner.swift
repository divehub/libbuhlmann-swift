import Foundation

/// Represents a user-defined stop for planning purposes.
public struct PlanningStop: Sendable {
    public let depth: Double
    public let time: Double
    public let gas: Gas

    public init(depth: Double, time: Double, gas: Gas) {
        self.depth = depth
        self.time = time
        self.gas = gas
    }
}

/// Helper class to generate a dive profile from user-defined stops.
public struct DivePlanner: Sendable {
    public init() {}

    /// Generate a full dive profile (with travel segments) from a list of stops.
    /// - Parameters:
    ///   - stops: List of target stops (depth, time, gas).
    ///   - descentRate: Descent rate in m/min (default 20 m/min).
    ///   - ascentRate: Ascent rate in m/min (default 10 m/min).
    /// - Returns: A `DiveProfile` containing all travel and hold segments.
    public func plan(
        stops: [PlanningStop],
        descentRate: Double = 20.0,
        ascentRate: Double = 10.0
    ) -> DiveProfile {
        var profile = DiveProfile()
        var currentDepth = 0.0

        for stop in stops {
            // 1. Travel to stop depth
            if stop.depth != currentDepth {
                let rate = (stop.depth > currentDepth) ? descentRate : ascentRate
                // Note: We use the stop's gas for travel.
                // In reality, descent gas might be different, but for simple planning this is standard.
                profile.addTravel(to: stop.depth, rate: rate, gas: stop.gas)
                currentDepth = stop.depth
            }

            // 2. Hold at stop
            if stop.time > 0 {
                profile.addHold(time: stop.time, gas: stop.gas)
            }
        }

        return profile
    }
}
