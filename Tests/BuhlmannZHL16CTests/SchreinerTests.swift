import XCTest

@testable import BuhlmannZHL16C

final class SchreinerTests: XCTestCase {

    func testSchreinerDecay() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // Instantaneous descent to 30m (4 bar)
        // Then stay for 10 mins.
        // Compartment 1 (4 min HT) should be significantly loaded.

        let depth = 30.0
        let time = 10.0
        engine.addSegment(startDepth: depth, endDepth: depth, time: time, gas: Gas.air)

        // Check Compartment 1
        // Initial pN2 = 0.79 * (1.01325 - 0.0627) = 0.751
        // Target pN2 = 0.79 * (4.01325 - 0.0627) = 3.121
        // After 10 mins (2.5 half-times), it should be close to target.
        // P = P_alv + (P_i - P_alv) * exp(-k*t)
        // k = ln(2)/4 = 0.1732
        // exp(-1.732) ~= 0.176
        // P ~= 3.121 + (0.751 - 3.121) * 0.176
        // P ~= 3.121 - 0.417 = 2.704

        let comp1 = engine.compartments[0]
        XCTAssertGreaterThan(comp1.pN2, 2.5)
        XCTAssertLessThan(comp1.pN2, 3.0)

        // Compartment 16 (635 min HT) should be barely changed.
        let comp16 = engine.compartments[15]
        XCTAssertLessThan(comp16.pN2, 0.8)
    }

    /// Test Schreiner equation with precise expected values
    func testSchreinerEquationPrecision() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // At 30m for 4 minutes (1 half-time for compartment 1)
        let depth = 30.0
        let time = 4.0  // Exactly 1 half-time for compartment 1

        engine.addSegment(startDepth: depth, endDepth: depth, time: time, gas: Gas.air)

        // After 1 half-time, tissue should be halfway to saturation
        // Initial: 0.79 * (1.01325 - 0.0627) ≈ 0.751 bar
        // Target: 0.79 * (P_30m - 0.0627) where P_30m ≈ 4.037 bar
        // Target ≈ 3.139 bar
        // After 1 half-time: initial + 0.5 * (target - initial)
        // ≈ 0.751 + 0.5 * (3.139 - 0.751) = 0.751 + 1.194 = 1.945

        let comp1 = engine.compartments[0]
        XCTAssertEqual(
            comp1.pN2, 1.945, accuracy: 0.05,
            "After 1 half-time, tissue should be ~halfway saturated")
    }

    func testInitialization() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // Check first compartment (fastest)
        // pN2 = (1.01325 - 0.0627) * 0.79 = 0.7509
        let expectedPN2 = (1.01325 - 0.0627) * 0.79
        XCTAssertEqual(engine.compartments[0].pN2, expectedPN2, accuracy: 0.001)
    }

    func testTissueLoading() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // Descent to 30m in 2 mins (15m/min)
        engine.addSegment(startDepth: 0, endDepth: 30, time: 2, gas: Gas.air)

        // Check loading after descent
        let pN2AfterDescent = engine.compartments[0].pN2
        XCTAssertGreaterThan(pN2AfterDescent, 0.7509)

        // Hold at 30m for 10 mins
        engine.addSegment(startDepth: 30, endDepth: 30, time: 10, gas: Gas.air)

        let pN2AfterHold = engine.compartments[0].pN2
        XCTAssertGreaterThan(
            pN2AfterHold, pN2AfterDescent, "Tissues should continue loading during hold")
    }

    /// Test that off-gassing works correctly during ascent
    func testOffGassingDuringAscent() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // Load tissues at 40m
        engine.addSegment(startDepth: 0, endDepth: 40, time: 2, gas: Gas.air)
        engine.addSegment(startDepth: 40, endDepth: 40, time: 20, gas: Gas.air)

        // Record tissue loading at depth
        let pN2AtDepth = engine.compartments.map { $0.pN2 }

        // Slow ascent to 6m (simulating stop)
        engine.addSegment(startDepth: 40, endDepth: 6, time: 10, gas: Gas.air)

        // Fast tissues should be off-gassing
        let pN2AfterAscent = engine.compartments.map { $0.pN2 }

        // Compartment 1 (fastest) should have reduced N2
        XCTAssertLessThan(
            pN2AfterAscent[0], pN2AtDepth[0],
            "Fast tissue should off-gas during ascent")

        // Compartment 16 (slowest) should still be loading (or nearly constant)
        // because the slower tissues have very slow off-gassing
        // At 6m depth, they're still slightly on-gassing from surface equilibrium
    }

    /// Test helium handling for trimix dives
    func testHeliumKinetics() {
        var engine = BuhlmannZHL16C()
        let trimix = try! Gas(o2: 0.21, he: 0.35)  // TMX 21/35
        engine.initializeTissues(gas: Gas.air)  // Start saturated with air

        // Descend on trimix
        engine.addSegment(startDepth: 0, endDepth: 50, time: 2.5, gas: trimix)
        engine.addSegment(startDepth: 50, endDepth: 50, time: 20, gas: trimix)

        // Check He loading in fast tissue
        let comp1 = engine.compartments[0]
        XCTAssertGreaterThan(comp1.pHe, 0, "Fast tissue should have He loading")

        // He should load faster than N2 (He has ~2.65x shorter half-time)
        // So relative saturation should be higher for He in fast tissues

        // Also verify N2 loading is reduced compared to air dive
        var airEngine = BuhlmannZHL16C()
        airEngine.initializeTissues(gas: Gas.air)
        airEngine.addSegment(startDepth: 0, endDepth: 50, time: 2.5, gas: Gas.air)
        airEngine.addSegment(startDepth: 50, endDepth: 50, time: 20, gas: Gas.air)

        XCTAssertLessThan(
            comp1.pN2, airEngine.compartments[0].pN2,
            "Trimix should result in less N2 loading than air")
    }

    /// Test M-value calculation for mixed gas
    func testMValueMixedGas() {
        var engine = BuhlmannZHL16C()
        let trimix = try! Gas(o2: 0.18, he: 0.45)  // TMX 18/45
        engine.initializeTissues(gas: trimix)

        // Load tissues
        engine.addSegment(startDepth: 0, endDepth: 60, time: 3, gas: trimix)
        engine.addSegment(startDepth: 60, endDepth: 60, time: 15, gas: trimix)

        // M-value should be weighted average of N2 and He coefficients
        let compartment = engine.compartments[0]
        let mValueAt3m = compartment.mValue(pressure: PressureConverter.metersToBar(depth: 3))

        // M-value should be positive and reasonable
        XCTAssertGreaterThan(mValueAt3m, 0)
        XCTAssertLessThan(mValueAt3m, 10)  // Sanity check
    }
}
