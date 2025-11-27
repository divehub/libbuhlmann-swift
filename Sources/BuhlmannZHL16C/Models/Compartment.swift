import Foundation

/// Represents a single tissue compartment.
public struct Compartment: Identifiable, Sendable {
    public let id: Int

    // Current Gas Loadings (Pressure in bar)
    public var pN2: Double
    public var pHe: Double

    // Constants for this compartment
    private let n2HalfTime: Double
    private let n2A: Double
    private let n2B: Double

    private let heHalfTime: Double
    private let heA: Double
    private let heB: Double

    /// Initialize a compartment with specific ZHL-16C constants.
    init(id: Int, n2Values: ZHL16CConstants.TissueValues, heValues: ZHL16CConstants.TissueValues) {
        self.id = id
        self.pN2 = 0.79  // Default initialization, will be overwritten by surface pressure usually
        self.pHe = 0.0

        self.n2HalfTime = n2Values.halfTime
        self.n2A = n2Values.a
        self.n2B = n2Values.b

        self.heHalfTime = heValues.halfTime
        self.heA = heValues.a
        self.heB = heValues.b
    }

    /// Initialize all 16 compartments.
    public static func createAll() -> [Compartment] {
        var compartments: [Compartment] = []
        for i in 0..<16 {
            let n2 = ZHL16CConstants.n2Values[i]
            let he = ZHL16CConstants.heValues[i]
            compartments.append(Compartment(id: i + 1, n2Values: n2, heValues: he))
        }
        return compartments
    }

    // Calculated properties for physics
    var n2K: Double { log(2) / n2HalfTime }
    var heK: Double { log(2) / heHalfTime }

    // M-value calculation helpers will go here or in the engine
    public func mValue(pressure: Double) -> Double {
        // Bühlmann M-value formula: P = (P_amb / b) + a
        // But we need to combine N2 and He.
        // a = (aN2 * pN2 + aHe * pHe) / (pN2 + pHe)
        // b = (bN2 * pN2 + bHe * pHe) / (pN2 + pHe)

        let totalInert = pN2 + pHe
        // Use epsilon comparison instead of == 0 for floating point safety
        if totalInert < 1e-10 { return 0 }

        let a = (n2A * pN2 + heA * pHe) / totalInert
        let b = (n2B * pN2 + heB * pHe) / totalInert

        return (pressure / b) + a
    }

    // Tolerable Ambient Pressure
    public func tolerableAmbientPressure(gf: Double) -> Double {
        // With Gradient Factors:
        // M_gradient = P_amb + GF * (M_value - P_amb)
        // We want to find P_amb such that P_inert <= M_gradient
        // This is circular if we use the standard definition.
        // Standard formula for Ceiling with GF:
        // P_amb_tol = (P_inert - a * GF) / (GF / b + 1.0 - GF)

        let totalInert = pN2 + pHe
        // Use epsilon comparison instead of == 0 for floating point safety
        if totalInert < 1e-10 { return 0 }

        let a = (n2A * pN2 + heA * pHe) / totalInert
        let b = (n2B * pN2 + heB * pHe) / totalInert

        return (totalInert - a * gf) / (gf / b + 1.0 - gf)
    }
}
