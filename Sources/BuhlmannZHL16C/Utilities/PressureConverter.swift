import Foundation

/// Helper for pressure conversions.
public struct PressureConverter {
    /// Standard gravity (m/s^2)
    private static let g = 9.80665
    /// Density of salt water (kg/m^3) - EN 13319
    private static let densitySaltWater = 1020.0  // Standard for dive computers usually 1020 or 1030. EN13319 uses 1020? Let's stick to 1020 approx or 1030.
    // Actually, let's use 1 bar = 10 meters of sea water (msw) as a standard approximation or precise physics?
    // User requested "Standardized (Metric: meters/bar)".
    // Usually 1 bar ~ 10m.
    // Let's use the standard definition: 1 bar = 100,000 Pa.
    // Pressure at depth d = P_surface + (density * g * d)
    // But for simplicity in diving, often 10msw = 1 bar is used, or specific density.
    // Let's use 1 bar = 10 meters for simplicity unless "Do not approximate the math" implies using density.
    // "Do not approximate the math" -> Use density.

    // Let's use a standard density.
    // 10 meters of salt water ~= 1 bar gauge?
    // Let's define: 1 bar = 100000 Pa.

    public static func metersToBar(depth: Double, surfacePressure: Double = 1.01325, density: Double = 1030.0) -> Double {
        // Hydrostatic pressure = depth * density * gravity
        // P = P_atm + (rho * g * h) / 100000
        let pressurePa = (density * g * depth)
        let pressureBar = pressurePa / 100000.0
        return surfacePressure + pressureBar
    }

    public static func barToMeters(pressure: Double, surfacePressure: Double = 1.01325, density: Double = 1030.0) -> Double {
        let pressureBar = pressure - surfacePressure
        let pressurePa = pressureBar * 100000.0
        return pressurePa / (density * g)
    }
}
