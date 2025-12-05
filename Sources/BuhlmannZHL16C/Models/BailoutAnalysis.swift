import Foundation

/// Result of a bailout analysis for a CCR dive.
///
/// Contains the bailout point details, CCR segments leading up to bailout,
/// and the OC bailout ascent schedule.
public struct BailoutAnalysis: Sendable {
    /// The depth at which bailout occurs (typically the point with longest TTS).
    public let bailoutDepth: Double

    /// The Time To Surface from the bailout point (including troubleshooting time).
    public let bailoutTTS: Double

    /// The CCR segments from dive start up to the bailout point.
    /// These segments contain the effective gas at each depth for tissue simulation.
    public let ccrSegmentsToBailout: [DiveSegment]

    /// The OC deco schedule for ascending from the bailout point.
    /// Includes troubleshooting segment if configured.
    public let bailoutSchedule: [DiveSegment]

    public init(
        bailoutDepth: Double,
        bailoutTTS: Double,
        ccrSegmentsToBailout: [DiveSegment],
        bailoutSchedule: [DiveSegment],
    ) {
        self.bailoutDepth = bailoutDepth
        self.bailoutTTS = bailoutTTS
        self.ccrSegmentsToBailout = ccrSegmentsToBailout
        self.bailoutSchedule = bailoutSchedule
    }
}
