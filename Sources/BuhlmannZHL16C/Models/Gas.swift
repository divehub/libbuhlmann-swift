import Foundation

/// Represents a breathing gas mixture.
public struct Gas: Equatable, Sendable, Codable, Hashable {
    /// Fraction of Oxygen (0.0 - 1.0)
    public let o2: Double
    /// Fraction of Helium (0.0 - 1.0)
    public let he: Double
    /// Fraction of Nitrogen (0.0 - 1.0)
    public let n2: Double
    /// Maximum Operating Depth in meters (optional, nil means unlimited)
    public let maxDepth: Double?

    /// Creates a new Gas mixture.
    /// - Parameters:
    ///   - o2: Fraction of Oxygen.
    ///   - he: Fraction of Helium.
    ///   - maxDepth: Maximum operating depth in meters (optional).
    /// - Throws: GasError.invalidFractions if the sum of fractions is not approximately 1.0.
    public init(o2: Double, he: Double, maxDepth: Double? = nil) throws {
        self.o2 = o2
        self.he = he
        self.n2 = 1.0 - o2 - he
        self.maxDepth = maxDepth

        guard n2 >= -0.0001 else {
            throw GasError.invalidFractions
        }

        // Ensure total is close to 1.0 (allowing for small floating point errors)
        let total = o2 + he + n2
        guard abs(total - 1.0) < 0.0001 else {
            throw GasError.invalidFractions
        }
    }

    /// Creates a copy of this gas with a specified max depth
    public func withMaxDepth(_ depth: Double) -> Gas {
        try! Gas(o2: o2, he: he, maxDepth: depth)
    }

    /// Check if this gas is safe to breathe at the given depth
    public func isSafe(atDepth depth: Double) -> Bool {
        guard let maxDepth = maxDepth else { return true }
        return depth <= maxDepth
    }

    /// Standard Air (21% O2, 79% N2)
    public static let air = try! Gas(o2: 0.21, he: 0.0)

    /// Pure Oxygen (100% O2)
    public static let oxygen = try! Gas(o2: 1.0, he: 0.0)

    /// EAN32 (32% O2)
    public static let ean32 = try! Gas(o2: 0.32, he: 0.0)

    /// EAN36 (36% O2)
    public static let ean36 = try! Gas(o2: 0.36, he: 0.0)

    /// EAN50 (50% O2)
    public static let nx50 = try! Gas(o2: 0.50, he: 0.0)

    // MARK: - CCR Support

    /// Calculate the effective breathing gas for CCR at a given depth.
    ///
    /// CCR maintains a constant ppO2 setpoint. The O2 fraction varies with depth:
    /// - `fO2 = setpoint / ambientPressure`
    /// - If setpoint > ambient pressure, fO2 is clamped to 1.0
    /// - Inert gas fractions scale from diluent proportionally
    ///
    /// - Parameters:
    ///   - depth: Current depth in meters.
    ///   - setpoint: Target ppO2 in bar (e.g., 1.3).
    ///   - diluent: The diluent gas (provides N2/He ratios).
    ///   - surfacePressure: Surface pressure in bar (default 1.01325).
    /// - Returns: A Gas representing the effective breathing mix at this depth.
    public static func effectiveGas(
        atDepth depth: Double,
        setpoint: Double,
        diluent: Gas,
        surfacePressure: Double = 1.01325
    ) throws -> Gas {
        // Calculate ambient pressure at depth
        // Using standard seawater density (1030 kg/m³)
        let ambientPressure = surfacePressure + (depth * 1030.0 * 9.80665 / 100000.0)

        // Clamp setpoint to ambient pressure (can't have ppO2 > ambient)
        let effectiveSetpoint = min(setpoint, ambientPressure)

        // Calculate O2 fraction
        let fO2 = effectiveSetpoint / ambientPressure

        // Calculate inert gas fraction
        let fInert = 1.0 - fO2

        // Scale N2 and He from diluent ratios
        let diluentInert = diluent.n2 + diluent.he
        guard diluentInert - fInert > 0.0001 else {
            // Diluent doesn't have enough inert gas to achieve required mix
            throw GasError.cannotDilute
        }
        let fHe: Double

        if diluentInert > 0.0001 {
            fHe = fInert * (diluent.he / diluentInert)
        } else {
            // Edge case: pure O2 diluent (unusual but handle it)
            fHe = 0.0
        }

        // Create and return the effective gas (this won't throw since we calculated correctly)
        return try! Gas(o2: fO2, he: fHe)
    }
}

public enum GasError: Error {
    case invalidFractions
    case cannotDilute
}
