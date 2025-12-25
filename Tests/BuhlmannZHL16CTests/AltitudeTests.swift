import XCTest

@testable import BuhlmannZHL16C

final class AltitudeTests: XCTestCase {

    private let seaLevelPressure = 1.01325
    private let altitudePressure = 0.82
    private let waterDensity = 1000.0  // Fresh water

    private func makeDecoGas(
        o2: Double,
        he: Double,
        surfacePressure: Double
    ) throws -> Gas {
        let gas = try Gas(o2: o2, he: he)
        let absolutePressure = 1.6 / o2
        let mod = PressureConverter.barToMeters(
            pressure: absolutePressure,
            surfacePressure: surfacePressure,
            density: waterDensity
        )
        return gas.withMaxDepth(mod)
    }

    private func runDecoSchedule(
        surfacePressure: Double,
        initialSurfacePressure: Double
    ) throws -> [DiveSegment] {
        let bottomGas = try Gas(o2: 0.10, he: 0.55)  // Tx10/55
        let decoGases = try [
            makeDecoGas(o2: 0.18, he: 0.35, surfacePressure: surfacePressure),  // Tx18/35
            makeDecoGas(o2: 0.40, he: 0.15, surfacePressure: surfacePressure),  // Tx40/15
            makeDecoGas(o2: 0.80, he: 0.00, surfacePressure: surfacePressure)   // EAN80
        ]

        var engine = BuhlmannZHL16C(
            surfacePressure: surfacePressure,
            waterDensity: waterDensity,
            initialSurfacePressure: initialSurfacePressure
        )

        // 120m for 5 minutes, descent at 20m/min
        let descentTime = 120.0 / 20.0
        engine.addSegment(startDepth: 0, endDepth: 120, time: descentTime, gas: bottomGas)
        engine.addSegment(startDepth: 120, endDepth: 120, time: 5.0, gas: bottomGas)

        let config = DecoConfig(
            ascentRate: 9.0,
            surfaceRate: 9.0,
            stopIncrement: 3.0,
            lastStopDepth: 3.0,
            gasSwitchTime: 0.0,
            gasSwitchMode: .disabled
        )

        return try engine.calculateDecoStops(
            gfLow: 0.50,
            gfHigh: 0.70,
            currentDepth: 120.0,
            bottomGas: bottomGas,
            decoGases: decoGases,
            config: config
        )
    }

    private func totalDecoTime(_ segments: [DiveSegment]) -> Double {
        segments.reduce(0) { $0 + $1.time }
    }

    private func shallowStopTime(_ segments: [DiveSegment]) -> Double {
        segments.reduce(0) { total, segment in
            guard abs(segment.startDepth - segment.endDepth) < 0.01,
                  segment.startDepth <= 9.0 + 0.01
            else { return total }
            return total + segment.time
        }
    }

    func testAltitudeInitialSurfacePressureIncreasesTotalDecoTime() throws {
        let acclimated = try runDecoSchedule(
            surfacePressure: altitudePressure,
            initialSurfacePressure: altitudePressure
        )
        let seaLevelSaturated = try runDecoSchedule(
            surfacePressure: altitudePressure,
            initialSurfacePressure: seaLevelPressure
        )

        let acclimatedTotal = totalDecoTime(acclimated)
        let seaLevelTotal = totalDecoTime(seaLevelSaturated)

        XCTAssertGreaterThan(
            seaLevelTotal,
            acclimatedTotal + 10.0,
            "Sea-level saturation should add meaningful deco time at altitude"
        )
    }

    func testAltitudeInitialSurfacePressureAddsShallowStopTime() throws {
        let acclimated = try runDecoSchedule(
            surfacePressure: altitudePressure,
            initialSurfacePressure: altitudePressure
        )
        let seaLevelSaturated = try runDecoSchedule(
            surfacePressure: altitudePressure,
            initialSurfacePressure: seaLevelPressure
        )

        let acclimatedShallow = shallowStopTime(acclimated)
        let seaLevelShallow = shallowStopTime(seaLevelSaturated)

        XCTAssertGreaterThan(
            seaLevelShallow,
            acclimatedShallow + 5.0,
            "Sea-level saturation should increase shallow stop time at altitude"
        )
    }
}
