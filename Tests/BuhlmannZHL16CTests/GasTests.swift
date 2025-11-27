import XCTest

@testable import BuhlmannZHL16C

final class GasTests: XCTestCase {

    // MARK: - Gas Validation Tests

    func testGasValidation() {
        XCTAssertNoThrow(try Gas(o2: 0.21, he: 0.0))
        XCTAssertNoThrow(try Gas(o2: 0.18, he: 0.35))  // Trimix 18/35

        XCTAssertThrowsError(try Gas(o2: 1.1, he: 0.0))
        XCTAssertThrowsError(try Gas(o2: 0.21, he: 0.8))  // Sum > 1.0
    }

    // MARK: - CCR Effective Gas Tests

    /// Test effectiveGas calculation at various depths
    func testCCREffectiveGas() throws {
        // Use hypoxic diluent (10/50) for deep CCR diving - 90% inert gas
        let diluent = try! Gas(o2: 0.10, he: 0.50)  // Trimix 10/50 diluent
        let setpoint = 1.3  // ppO2 setpoint

        // At 30m (ambient ~4.0 bar): fO2 = 1.3/4.0 = 0.325
        let gas30m = try Gas.effectiveGas(atDepth: 30, setpoint: setpoint, diluent: diluent)
        XCTAssertEqual(gas30m.o2, 0.325, accuracy: 0.02, "fO2 at 30m should be ~0.325")

        // Verify inert gas ratios match diluent
        let diluentInertRatio = diluent.he / (diluent.he + diluent.n2)
        let effectiveInertRatio = gas30m.he / (gas30m.he + gas30m.n2)
        XCTAssertEqual(
            effectiveInertRatio, diluentInertRatio, accuracy: 0.01,
            "He/inert ratio should match diluent")

        // At 60m (ambient ~7.0 bar): fO2 = 1.3/7.0 = 0.186
        // With 10/50 diluent (90% inert), we can achieve the required 81.4% inert
        let gas60m = try Gas.effectiveGas(atDepth: 60, setpoint: setpoint, diluent: diluent)
        XCTAssertEqual(gas60m.o2, 0.184, accuracy: 0.02, "fO2 at 60m should be ~0.184")

        // At surface (1.01325 bar): fO2 = 1.3/1.01325 > 1.0, should clamp to 1.0
        let gasSurface = try Gas.effectiveGas(atDepth: 0, setpoint: setpoint, diluent: diluent)
        XCTAssertEqual(gasSurface.o2, 1.0, accuracy: 0.01, "fO2 at surface should clamp to 1.0")
        XCTAssertEqual(gasSurface.he, 0.0, accuracy: 0.01, "He at surface should be 0 when fO2=1.0")
    }

    /// Test setpoint clamping at shallow depths
    func testCCRSetpointClamping() throws {
        let diluent = Gas.air
        let setpoint = 1.4  // High setpoint

        // At 3m (ambient ~1.31 bar): setpoint 1.4 > ambient, should clamp
        let gas3m = try Gas.effectiveGas(atDepth: 3, setpoint: setpoint, diluent: diluent)
        XCTAssertLessThanOrEqual(gas3m.o2, 1.0, "fO2 should never exceed 1.0")
        // Effective setpoint should be ~1.31 bar, so fO2 ≈ 1.0
        XCTAssertGreaterThan(gas3m.o2, 0.95, "fO2 at 3m with 1.4 setpoint should be near 1.0")

        // At 6m (ambient ~1.62 bar): setpoint 1.4 < ambient, no clamping needed
        let gas6m = try Gas.effectiveGas(atDepth: 6, setpoint: setpoint, diluent: diluent)
        XCTAssertEqual(gas6m.o2, 1.4 / 1.62, accuracy: 0.02, "fO2 at 6m should be setpoint/ambient")
    }

    /// Test that effectiveGas throws cannotDilute when diluent has too much O2
    func testCCREffectiveGasCannotDilute() {
        // High O2 diluent (e.g., EAN50)
        let highO2Diluent = try! Gas(o2: 0.50, he: 0.0)
        let setpoint = 1.3

        // At shallow depth where required fO2 > diluent can provide
        // At 6m (ambient ~1.62 bar): required fO2 = 1.3/1.62 ≈ 0.80
        // With EAN50 diluent (50% O2, 50% N2), the diluent's inert fraction is 0.50
        // Required inert fraction = 1.0 - 0.80 = 0.20
        // Since required inert (0.20) < diluent inert (0.50), this should work
        XCTAssertNoThrow(
            try Gas.effectiveGas(atDepth: 6, setpoint: setpoint, diluent: highO2Diluent),
            "EAN50 at 6m with SP 1.3 should work")

        // Pure O2 diluent - can never provide inert gas
        let pureO2Diluent = Gas.oxygen
        // At any depth where setpoint < ambient pressure, we need some inert gas
        // At 30m (ambient ~4.0 bar): required fO2 = 1.3/4.0 = 0.325, required inert = 0.675
        // Pure O2 has 0% inert gas - cannot dilute
        XCTAssertThrowsError(
            try Gas.effectiveGas(atDepth: 30, setpoint: setpoint, diluent: pureO2Diluent),
            "Pure O2 diluent should throw cannotDilute at depth"
        ) { error in
            XCTAssertEqual(error as? GasError, GasError.cannotDilute)
        }

        // High O2 diluent at deep depth where it can't achieve the setpoint
        // At 3m (ambient ~1.31 bar): required fO2 = 1.3/1.31 ≈ 0.99, required inert ≈ 0.01
        // EAN50 has 50% inert - more than enough, this should work
        XCTAssertNoThrow(
            try Gas.effectiveGas(atDepth: 3, setpoint: setpoint, diluent: highO2Diluent),
            "EAN50 at 3m should work (setpoint nearly matches ambient)")
    }

    /// Test edge cases for cannotDilute error
    func testCCREffectiveGasCannotDiluteEdgeCases() {
        // Very high O2 diluent (90% O2)
        let veryHighO2 = try! Gas(o2: 0.90, he: 0.0)

        // At surface with setpoint 0.7 - required fO2 = 0.7/1.01 ≈ 0.69
        // Required inert = 0.31, diluent has 0.10 inert
        // 0.10 < 0.31, so cannot dilute
        XCTAssertThrowsError(
            try Gas.effectiveGas(atDepth: 0, setpoint: 0.7, diluent: veryHighO2),
            "90% O2 diluent cannot achieve SP 0.7 at surface"
        ) { error in
            XCTAssertEqual(error as? GasError, GasError.cannotDilute)
        }

        // At depth where it CAN work - deeper means lower required fO2
        // At 40m (ambient ~5.0 bar): required fO2 = 0.7/5.0 = 0.14
        // Required inert = 0.86, but diluent only has 0.10 inert
        // Still cannot dilute!
        XCTAssertThrowsError(
            try Gas.effectiveGas(atDepth: 40, setpoint: 0.7, diluent: veryHighO2),
            "90% O2 diluent cannot achieve SP 0.7 even at 40m"
        ) { error in
            XCTAssertEqual(error as? GasError, GasError.cannotDilute)
        }

        // Now with a lower setpoint that the high O2 diluent CAN achieve
        // At 40m with SP 1.3: required fO2 = 1.3/5.0 = 0.26, required inert = 0.74
        // Still needs 0.74 inert but diluent only has 0.10 - cannot dilute
        XCTAssertThrowsError(
            try Gas.effectiveGas(atDepth: 40, setpoint: 1.3, diluent: veryHighO2),
            "90% O2 diluent cannot provide enough inert gas at 40m"
        ) { error in
            XCTAssertEqual(error as? GasError, GasError.cannotDilute)
        }

        // Normal air diluent should always work
        let airDiluent = Gas.air
        XCTAssertNoThrow(
            try Gas.effectiveGas(atDepth: 40, setpoint: 1.3, diluent: airDiluent),
            "Air diluent should work at any reasonable depth/setpoint")
        XCTAssertNoThrow(
            try Gas.effectiveGas(atDepth: 0, setpoint: 0.7, diluent: airDiluent),
            "Air diluent should work at surface with low setpoint")
    }

    /// Test trimix diluent behavior with effectiveGas
    func testCCREffectiveGasTrimixDiluent() throws {
        // Trimix 21/35 diluent
        let trimixDiluent = try! Gas(o2: 0.21, he: 0.35)

        // At 50m with SP 1.3: should work fine
        let gas50m = try Gas.effectiveGas(atDepth: 50, setpoint: 1.3, diluent: trimixDiluent)
        XCTAssertGreaterThan(gas50m.he, 0, "Should have helium in effective gas")
        XCTAssertGreaterThan(gas50m.n2, 0, "Should have nitrogen in effective gas")

        // Verify He/N2 ratio matches diluent
        let diluentHeN2Ratio = trimixDiluent.he / trimixDiluent.n2
        let effectiveHeN2Ratio = gas50m.he / gas50m.n2
        XCTAssertEqual(
            effectiveHeN2Ratio, diluentHeN2Ratio, accuracy: 0.01,
            "He/N2 ratio should match diluent")

        // Hypoxic trimix 10/70 - very low O2
        let hypoxicTrimix = try! Gas(o2: 0.10, he: 0.70)

        // At 100m with SP 1.3: should work
        let gas100m = try Gas.effectiveGas(atDepth: 100, setpoint: 1.3, diluent: hypoxicTrimix)
        XCTAssertGreaterThan(gas100m.he, 0.5, "Deep dive should have significant He")
    }
}
