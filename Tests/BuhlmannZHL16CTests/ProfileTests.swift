import XCTest

@testable import BuhlmannZHL16C

final class ProfileTests: XCTestCase {

    func testMultiLevelProfile() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues()

        var profile = DiveProfile()
        // Descent to 30m
        profile.addSegment(DiveSegment(startDepth: 0, endDepth: 30, time: 2, gas: Gas.air))
        // Bottom at 30m for 20 mins
        profile.addSegment(DiveSegment(startDepth: 30, endDepth: 30, time: 20, gas: Gas.air))
        // Ascent to 15m
        profile.addSegment(DiveSegment(startDepth: 30, endDepth: 15, time: 2, gas: Gas.air))
        // Hold at 15m for 10 mins
        profile.addSegment(DiveSegment(startDepth: 15, endDepth: 15, time: 10, gas: Gas.air))

        engine.runProfile(profile)

        let ndl = engine.ndl(depth: 15, gas: Gas.air, gf: 1.0)
        print("NDL at 15m after multi-level: \(ndl)")

        XCTAssertGreaterThan(ndl, 0)
    }

    func testGasSwitching() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues()

        // Deep dive on Air to 50m
        engine.addSegment(startDepth: 0, endDepth: 50, time: 3, gas: Gas.air)
        engine.addSegment(startDepth: 50, endDepth: 50, time: 20, gas: Gas.air)

        // Switch to EAN50 at 21m
        let ean50 = try! Gas(o2: 0.5, he: 0.0)
        engine.addSegment(startDepth: 50, endDepth: 21, time: 3, gas: Gas.air)
        engine.addSegment(startDepth: 21, endDepth: 21, time: 10, gas: ean50)

        // Check that N2 loading slows down (or off-gassing starts faster)
        // compared to staying on Air.
        // This is a bit complex to assert simply without a control.
        // But we can check that pN2 is lower than if we stayed on air.

        let pN2WithSwitch = engine.compartments[0].pN2

        var controlEngine = BuhlmannZHL16C()
        controlEngine.initializeTissues()
        controlEngine.addSegment(startDepth: 0, endDepth: 50, time: 3, gas: Gas.air)
        controlEngine.addSegment(startDepth: 50, endDepth: 50, time: 20, gas: Gas.air)
        controlEngine.addSegment(startDepth: 50, endDepth: 21, time: 3, gas: Gas.air)
        controlEngine.addSegment(startDepth: 21, endDepth: 21, time: 10, gas: Gas.air)

        let pN2WithoutSwitch = controlEngine.compartments[0].pN2

        XCTAssertLessThan(
            pN2WithSwitch, pN2WithoutSwitch, "Gas switch to EAN50 should reduce N2 loading")
    }

    func testMultiLevelDive() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues()

        // 30m for 15 mins
        engine.addSegment(startDepth: 0, endDepth: 30, time: 1.5, gas: Gas.air)
        engine.addSegment(startDepth: 30, endDepth: 30, time: 13.5, gas: Gas.air)

        // Ascend to 15m for 15 mins
        engine.addSegment(startDepth: 30, endDepth: 15, time: 1.5, gas: Gas.air)
        engine.addSegment(startDepth: 15, endDepth: 15, time: 13.5, gas: Gas.air)

        // Check NDL at 15m
        let ndl = engine.ndl(depth: 15, gas: Gas.air, gf: 0.85)
        print("NDL at 15m after multi-level: \(ndl)")
        XCTAssertGreaterThan(ndl, 0)
    }

    func testRepetitiveDive() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues()

        // Dive 1: 30m for 20 mins
        engine.addSegment(startDepth: 0, endDepth: 30, time: 2, gas: Gas.air)
        engine.addSegment(startDepth: 30, endDepth: 30, time: 18, gas: Gas.air)

        // Surface Interval: 1 hour
        engine.addSegment(startDepth: 0, endDepth: 0, time: 60, gas: Gas.air)

        // Check tissues are not fully desaturated
        // N2 pressure in slow tissues should be > 0.79
        let slowTissue = engine.compartments[15]
        XCTAssertGreaterThan(slowTissue.pN2, 0.79)
    }
}
