import Foundation

/// Represents a single segment of a dive.
public struct DiveSegment: Sendable {
    /// Depth at the start of the segment (meters).
    public let startDepth: Double
    /// Depth at the end of the segment (meters).
    public let endDepth: Double
    /// Duration of the segment (minutes).
    public let time: Double
    /// Breathing gas used during this segment.
    public let gas: Gas

    public init(startDepth: Double, endDepth: Double, time: Double, gas: Gas) {
        self.startDepth = startDepth
        self.endDepth = endDepth
        self.time = time
        self.gas = gas
    }
}

/// Represents a complete dive profile.
public struct DiveProfile: Sendable {
    public var segments: [DiveSegment]

    public init(segments: [DiveSegment] = []) {
        self.segments = segments
    }

    public mutating func addSegment(_ segment: DiveSegment) {
        segments.append(segment)
    }

    /// Helper to add a descent/ascent segment.
    public mutating func addTravel(to depth: Double, rate: Double = 20.0, gas: Gas) {
        let lastDepth = segments.last?.endDepth ?? 0.0
        let distance = abs(depth - lastDepth)
        let time = distance / rate
        addSegment(DiveSegment(startDepth: lastDepth, endDepth: depth, time: time, gas: gas))
    }

    /// Helper to add a constant depth segment (bottom/stop).
    public mutating func addHold(time: Double, gas: Gas) {
        let depth = segments.last?.endDepth ?? 0.0
        addSegment(DiveSegment(startDepth: depth, endDepth: depth, time: time, gas: gas))
    }
}
