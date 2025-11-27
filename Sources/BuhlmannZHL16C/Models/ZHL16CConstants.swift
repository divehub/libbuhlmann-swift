import Foundation

struct ZHL16CConstants {
    struct TissueValues {
        let halfTime: Double
        let a: Double
        let b: Double
    }

    // Nitrogen (N2) Constants
    static let n2Values: [TissueValues] = [
        TissueValues(halfTime: 4.0, a: 1.2599, b: 0.5050),
        TissueValues(halfTime: 8.0, a: 1.0000, b: 0.6514),
        TissueValues(halfTime: 12.5, a: 0.8618, b: 0.7222),
        TissueValues(halfTime: 18.5, a: 0.7562, b: 0.7825),
        TissueValues(halfTime: 27.0, a: 0.6667, b: 0.8126),
        TissueValues(halfTime: 38.3, a: 0.5600, b: 0.8434),
        TissueValues(halfTime: 54.3, a: 0.4947, b: 0.8693),
        TissueValues(halfTime: 77.0, a: 0.4500, b: 0.8910),
        TissueValues(halfTime: 109.0, a: 0.4187, b: 0.9092),
        TissueValues(halfTime: 146.0, a: 0.3798, b: 0.9222),
        TissueValues(halfTime: 187.0, a: 0.3497, b: 0.9319),
        TissueValues(halfTime: 239.0, a: 0.3223, b: 0.9403),
        TissueValues(halfTime: 305.0, a: 0.2850, b: 0.9477),
        TissueValues(halfTime: 390.0, a: 0.2737, b: 0.9544),
        TissueValues(halfTime: 498.0, a: 0.2523, b: 0.9602),
        TissueValues(halfTime: 635.0, a: 0.2327, b: 0.9653),
    ]

    // Helium (He) Constants
    static let heValues: [TissueValues] = [
        TissueValues(halfTime: 1.51, a: 1.7424, b: 0.4245),
        TissueValues(halfTime: 3.02, a: 1.3830, b: 0.5747),
        TissueValues(halfTime: 4.72, a: 1.1919, b: 0.6527),
        TissueValues(halfTime: 6.99, a: 1.0458, b: 0.7223),
        TissueValues(halfTime: 10.21, a: 0.9220, b: 0.7582),
        TissueValues(halfTime: 14.48, a: 0.8205, b: 0.7957),
        TissueValues(halfTime: 20.53, a: 0.7305, b: 0.8279),
        TissueValues(halfTime: 29.11, a: 0.6502, b: 0.8553),
        TissueValues(halfTime: 41.20, a: 0.5950, b: 0.8757),
        TissueValues(halfTime: 55.19, a: 0.5545, b: 0.8903),
        TissueValues(halfTime: 70.69, a: 0.5333, b: 0.8997),
        TissueValues(halfTime: 90.34, a: 0.5189, b: 0.9073),
        TissueValues(halfTime: 115.29, a: 0.5181, b: 0.9122),
        TissueValues(halfTime: 147.42, a: 0.5176, b: 0.9171),
        TissueValues(halfTime: 188.24, a: 0.5172, b: 0.9217),
        TissueValues(halfTime: 240.03, a: 0.5119, b: 0.9267),
    ]
}
