import XCTest

@testable import BuhlmannZHL16C

final class ConstantsTests: XCTestCase {

    func testConstants() {
        // Check Compartment 1 (fastest)
        let n2_1 = ZHL16CConstants.n2Values[0]
        XCTAssertEqual(n2_1.halfTime, 4.0)
        XCTAssertEqual(n2_1.a, 1.2599)

        // Check Compartment 16 (slowest)
        let n2_16 = ZHL16CConstants.n2Values[15]
        XCTAssertEqual(n2_16.halfTime, 635.0)
        XCTAssertEqual(n2_16.b, 0.9653)
    }

    /// Verify ZH-L16C constants match published literature values
    func testZHL16CConstantsCompleteness() {
        // Verify we have all 16 compartments
        XCTAssertEqual(ZHL16CConstants.n2Values.count, 16)
        XCTAssertEqual(ZHL16CConstants.heValues.count, 16)

        // Verify N2 half-times are in ascending order
        for i in 1..<16 {
            XCTAssertGreaterThan(
                ZHL16CConstants.n2Values[i].halfTime,
                ZHL16CConstants.n2Values[i - 1].halfTime,
                "N2 half-times should be in ascending order"
            )
        }

        // Verify He half-times are approximately 1/2.65 of N2 half-times
        for i in 0..<16 {
            let ratio = ZHL16CConstants.n2Values[i].halfTime / ZHL16CConstants.heValues[i].halfTime
            XCTAssertEqual(
                ratio, 2.65, accuracy: 0.1, "He/N2 ratio should be ~2.65 for compartment \(i+1)")
        }
    }

    /// Test pressure converter accuracy
    func testPressureConverterAccuracy() {
        // 10m of seawater should be approximately 1 bar
        let pressure10m = PressureConverter.metersToBar(depth: 10) - 1.01325
        XCTAssertEqual(pressure10m, 1.0, accuracy: 0.02, "10m should be ~1 bar gauge")

        // Round trip should be accurate
        let depth = 42.5
        let pressure = PressureConverter.metersToBar(depth: depth)
        let backToDepth = PressureConverter.barToMeters(pressure: pressure)
        XCTAssertEqual(backToDepth, depth, accuracy: 0.001, "Pressure conversion should round-trip")
    }

    /// Test water vapor pressure handling
    func testWaterVaporPressure() {
        var engine = BuhlmannZHL16C()

        // Water vapor pressure is ~0.0627 bar (47 mmHg at 37°C)
        // Initial tissue loading should account for this
        // pN2 = (1.01325 - 0.0627) * 0.79 ≈ 0.751 bar

        let expectedPN2 = (1.01325 - 0.0627) * 0.79
        XCTAssertEqual(engine.compartments[0].pN2, expectedPN2, accuracy: 0.001)

        // At depth, inspired ppN2 should also subtract water vapor
        // At 30m (~4.04 bar absolute), inspired pN2 = (4.04 - 0.0627) * 0.79 ≈ 3.14 bar
    }
}
