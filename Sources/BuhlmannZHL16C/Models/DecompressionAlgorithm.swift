import Foundation

/// Mode for handling gas switch timing
public enum GasSwitchMode: String, Sendable, Codable, CaseIterable, Identifiable {
    /// No gas switch time added - instant switch
    case disabled = "Disabled"
    /// Gas switch time is a minimum stop duration at switch depth
    case minimum = "Minimum"
    /// Gas switch time is added to any required stop time at switch depth
    case additive = "Additive"

    public var id: String { rawValue }
}

/// Configuration for decompression calculation
public struct DecoConfig: Sendable {
    /// Ascent rate in meters per minute
    public let ascentRate: Double
    /// Surface rate in meters per minute (used for final ascent from last stop to surface)
    public let surfaceRate: Double
    /// Stop increment in meters (typically 3m)
    public let stopIncrement: Double
    /// Last stop depth in meters (typically 3m or 6m)
    public let lastStopDepth: Double
    /// Gas switch time in minutes (time spent at stop when switching gas)
    public let gasSwitchTime: Double
    /// Mode for handling gas switch timing
    public let gasSwitchMode: GasSwitchMode
    /// CCR bailout troubleshooting time in minutes (time at depth after bailout before ascending)
    public let troubleshootingTime: Double

    public init(
        ascentRate: Double = 9.0,
        surfaceRate: Double = 3.0,
        stopIncrement: Double = 3.0,
        lastStopDepth: Double = 3.0,
        gasSwitchTime: Double = 1.0,
        gasSwitchMode: GasSwitchMode = .disabled,
        troubleshootingTime: Double = 0.0
    ) {
        self.ascentRate = ascentRate
        self.surfaceRate = surfaceRate
        self.stopIncrement = stopIncrement
        self.lastStopDepth = lastStopDepth
        self.gasSwitchTime = gasSwitchTime
        self.gasSwitchMode = gasSwitchMode
        self.troubleshootingTime = troubleshootingTime
    }

    /// Default configuration
    public static let `default` = DecoConfig()
}

/// Protocol defining the interface for a decompression algorithm.
public protocol DecompressionAlgorithm: Sendable {
    /// The tissue compartments being tracked.
    var compartments: [Compartment] { get set }

    /// Initialize tissues to surface pressure with a specific gas.
    mutating func initializeTissues(surfacePressure: Double, gas: Gas)

    /// Add a dive segment to the simulation (updating tissue loads).
    mutating func addSegment(
        startDepth: Double, endDepth: Double, time: Double, gas: Gas, surfacePressure: Double)

    /// Add a CCR segment to the simulation.
    /// CCR maintains constant ppO2, so gas fractions vary with depth.
    mutating func addCCRSegment(
        startDepth: Double,
        endDepth: Double,
        time: Double,
        diluent: Gas,
        setpoint: Double,
        surfacePressure: Double
    ) throws

    /// Calculate current ceiling (shallowest depth allowed) in meters.
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low.
    ///   - gfHigh: Gradient Factor High.
    ///   - fixedFirstStopDepth: Optional fixed depth to anchor GF slope.
    ///   - surfacePressure: Surface pressure in bar (default 1.01325 for sea level).
    /// - Returns: Ceiling depth in meters.
    func ceiling(
        gfLow: Double, gfHigh: Double, fixedFirstStopDepth: Double?, surfacePressure: Double
    ) -> Double

    /// Calculate No Decompression Limit (NDL) in minutes.
    /// - Parameters:
    ///   - depth: Current depth in meters.
    ///   - gas: Breathing gas.
    ///   - gf: Gradient Factor to use for the surfacing limit (usually GF_High).
    ///   - surfacePressure: Surface pressure in bar (default 1.01325 for sea level).
    /// - Returns: NDL in minutes. Returns 999 if NDL exceeds calculation limit.
    func ndl(depth: Double, gas: Gas, gf: Double, surfacePressure: Double) -> Double

    /// Calculate decompression stops required to surface (single gas).
    /// - Throws: `DecoError.maxDurationExceeded` if the calculated dive exceeds 24 hours.
    func calculateDecoStops(gfLow: Double, gfHigh: Double, currentDepth: Double, gas: Gas)
        throws -> [DiveSegment]

    /// Calculate decompression stops with multiple gases.
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low.
    ///   - gfHigh: Gradient Factor High.
    ///   - currentDepth: Current depth in meters.
    ///   - bottomGas: The gas used at the bottom (fallback if no deco gas available).
    ///   - decoGases: Available decompression gases with their max depths set.
    ///   - config: Decompression configuration.
    ///   - surfacePressure: Surface pressure in bar (default 1.01325 for sea level).
    /// - Returns: Array of DiveSegments representing the ascent profile.
    /// - Throws: `DecoError.maxDurationExceeded` if the calculated dive exceeds 24 hours.
    func calculateDecoStops(
        gfLow: Double,
        gfHigh: Double,
        currentDepth: Double,
        bottomGas: Gas,
        decoGases: [Gas],
        config: DecoConfig,
        surfacePressure: Double
    ) throws -> [DiveSegment]

    /// Calculate CCR decompression stops required to surface.
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low.
    ///   - gfHigh: Gradient Factor High.
    ///   - currentDepth: Current depth in meters.
    ///   - diluent: The CCR diluent gas.
    ///   - setpoint: Target ppO2 in bar for the ascent.
    ///   - config: Decompression configuration.
    ///   - surfacePressure: Surface pressure in bar.
    /// - Returns: Array of DiveSegments representing the CCR ascent profile.
    func calculateCCRDecoStops(
        gfLow: Double,
        gfHigh: Double,
        currentDepth: Double,
        diluent: Gas,
        setpoint: Double,
        config: DecoConfig,
        surfacePressure: Double
    ) throws -> [DiveSegment]

    /// Calculate Time To Surface for OC gas(es).
    /// - Throws: `DecoError.maxDurationExceeded` if the calculated dive exceeds 24 hours.
    func timeToSurface(
        gfLow: Double,
        gfHigh: Double,
        currentDepth: Double,
        bottomGas: Gas,
        decoGases: [Gas],
        config: DecoConfig,
        surfacePressure: Double
    ) throws -> Double

    /// Calculate Time To Surface for CCR.
    func timeToSurfaceCCR(
        gfLow: Double,
        gfHigh: Double,
        currentDepth: Double,
        diluent: Gas,
        setpoint: Double,
        config: DecoConfig,
        surfacePressure: Double
    ) throws -> Double

    /// Calculate the OC bailout plan for a CCR dive.
    /// Finds the point with the longest TTS and generates the bailout schedule.
    func calculateBailoutPlan(
        diveSegments: [(startDepth: Double, endDepth: Double, time: Double, setpoint: Double)],
        diluent: Gas,
        bailoutDecoGases: [Gas],
        troubleshootingTime: Double,
        gfLow: Double,
        gfHigh: Double,
        config: DecoConfig,
        surfacePressure: Double
    ) throws -> BailoutAnalysis
}
