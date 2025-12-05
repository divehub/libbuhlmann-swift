import XCTest

@testable import BuhlmannZHL16C

final class CCRTests: XCTestCase {

    /// Test addCCRSegment for constant depth
    func testCCRSegmentConstantDepth() throws {
        var engine = BuhlmannZHL16C()
        let diluent = try Gas(o2: 0.21, he: 0.35)
        engine.initializeTissues()

        // Add CCR segment at constant 30m for 20 minutes
        try engine.addCCRSegment(
            startDepth: 30, endDepth: 30, time: 20, diluent: diluent, setpoint: 1.3)

        // Compare with equivalent OC segment using effective gas
        var engineOC = BuhlmannZHL16C()
        engineOC.initializeTissues()
        let effectiveGas = try Gas.effectiveGas(atDepth: 30, setpoint: 1.3, diluent: diluent)
        engineOC.addSegment(startDepth: 30, endDepth: 30, time: 20, gas: effectiveGas)

        // Tissue loads should be identical
        for i in 0..<16 {
            XCTAssertEqual(
                engine.compartments[i].pN2, engineOC.compartments[i].pN2, accuracy: 0.001,
                "N2 load should match for compartment \(i+1)")
            XCTAssertEqual(
                engine.compartments[i].pHe, engineOC.compartments[i].pHe, accuracy: 0.001,
                "He load should match for compartment \(i+1)")
        }
    }

    /// Test addCCRSegment for depth-changing segment (discretization)
    func testCCRSegmentDepthChange() throws {
        var engine = BuhlmannZHL16C()
        let diluent = try Gas(o2: 0.21, he: 0.35)
        engine.initializeTissues()

        // Descend from 0 to 40m in 4 minutes (10m/min)
        try engine.addCCRSegment(
            startDepth: 0, endDepth: 40, time: 4, diluent: diluent, setpoint: 1.3)

        // Verify tissues have loaded - N2 and He should be elevated
        let initialN2 = (1.01325 - 0.0627) * diluent.n2  // Surface N2 tension
        XCTAssertGreaterThan(
            engine.compartments[0].pN2, initialN2,
            "Fast compartment N2 should increase during descent")

        // Ceiling should be near zero for short descent
        let ceiling = engine.ceiling(gfLow: 0.3, gfHigh: 0.7)
        XCTAssertEqual(ceiling, 0.0, accuracy: 1.0, "Short descent should have minimal ceiling")
    }

    /// Test CCR deco calculation
    func testCCRDecoStops() throws {
        var engine = BuhlmannZHL16C()
        let diluent = try Gas(o2: 0.21, he: 0.35)  // Trimix 21/35
        engine.initializeTissues()

        // Typical CCR dive: 40m for 30 minutes
        // Use setpoint 1.3 throughout - at 40m, fInert needed is 74.3%, diluent provides 79%
        try engine.addCCRSegment(
            startDepth: 0, endDepth: 40, time: 4, diluent: diluent, setpoint: 1.3)
        try engine.addCCRSegment(
            startDepth: 40, endDepth: 40, time: 30, diluent: diluent, setpoint: 1.3)

        // Calculate CCR deco with 1.3 setpoint
        let decoStops = try engine.calculateCCRDecoStops(
            gfLow: 0.3, gfHigh: 0.7, currentDepth: 40, diluent: diluent, setpoint: 1.3,
            config: .default)

        // Verify we have deco stops
        XCTAssertGreaterThan(decoStops.count, 0, "Should have deco stops after 40m/30min")

        // Verify segments end at surface
        if let lastSegment = decoStops.last {
            XCTAssertEqual(
                lastSegment.endDepth, 0, accuracy: 0.1, "Last segment should reach surface")
        }

        // Verify O2 fractions vary with depth (characteristic of CCR)
        if decoStops.count >= 2 {
            let deepStop = decoStops.first { $0.startDepth > 10 && $0.startDepth == $0.endDepth }
            let shallowStop = decoStops.first { $0.startDepth < 10 && $0.startDepth == $0.endDepth }

            if let deep = deepStop, let shallow = shallowStop {
                XCTAssertLessThan(
                    deep.gas.o2, shallow.gas.o2,
                    "Deep stop should have lower fO2 than shallow stop")
            }
        }

        print("\n=== CCR Deco (40m/30min, setpoint 1.3) ===")
        for stop in decoStops where stop.startDepth == stop.endDepth {
            print(
                "\(Int(stop.startDepth))m: \(Int(stop.time)) min (fO2: \(String(format: "%.2f", stop.gas.o2)))"
            )
        }
    }

    /// Test CCR vs OC deco comparison - CCR should generally have shorter deco
    func testCCRvsOCDecoComparison() throws {
        // CCR dive
        var ccrEngine = BuhlmannZHL16C()
        let diluent = try Gas(o2: 0.21, he: 0.35)
        ccrEngine.initializeTissues()
        try ccrEngine.addCCRSegment(
            startDepth: 0, endDepth: 40, time: 4, diluent: diluent, setpoint: 1.3)
        try ccrEngine.addCCRSegment(
            startDepth: 40, endDepth: 40, time: 20, diluent: diluent, setpoint: 1.3)

        let ccrDeco = try ccrEngine.calculateCCRDecoStops(
            gfLow: 0.3, gfHigh: 0.7, currentDepth: 40, diluent: diluent, setpoint: 1.3,
            config: .default)
        let ccrDecoTime = ccrDeco.filter { $0.startDepth == $0.endDepth }.reduce(0.0) {
            $0 + $1.time
        }

        // OC dive with same diluent as bottom gas (no deco gas switches for fair comparison)
        var ocEngine = BuhlmannZHL16C()
        ocEngine.initializeTissues()
        ocEngine.addSegment(startDepth: 0, endDepth: 40, time: 4, gas: diluent)
        ocEngine.addSegment(startDepth: 40, endDepth: 40, time: 20, gas: diluent)

        let ocDeco = try ocEngine.calculateDecoStops(
            gfLow: 0.3, gfHigh: 0.7, currentDepth: 40, bottomGas: diluent, decoGases: [],
            config: .default)
        let ocDecoTime = ocDeco.filter { $0.startDepth == $0.endDepth }.reduce(0.0) { $0 + $1.time }

        print("\n=== CCR vs OC Deco Comparison (40m/20min) ===")
        print("CCR deco time: \(ccrDecoTime) min")
        print("OC deco time: \(ocDecoTime) min")

        // CCR with 1.3 setpoint should have shorter deco than OC with same diluent
        // because CCR has higher effective O2 at all depths
        XCTAssertLessThan(
            ccrDecoTime, ocDecoTime,
            "CCR should have shorter deco than OC with same base gas")
    }

    /// Test CCR Time To Surface calculation
    func testTimeToSurfaceCCR() throws {
        var engine = BuhlmannZHL16C()
        let diluent = try Gas(o2: 0.21, he: 0.35)
        engine.initializeTissues()

        // CCR dive: 40m for 30 minutes
        try engine.addCCRSegment(
            startDepth: 0, endDepth: 40, time: 4, diluent: diluent, setpoint: 1.3)
        try engine.addCCRSegment(
            startDepth: 40, endDepth: 40, time: 30, diluent: diluent, setpoint: 1.3)

        let ttsCCR = try engine.timeToSurfaceCCR(
            gfLow: 0.3, gfHigh: 0.7, currentDepth: 40, diluent: diluent, setpoint: 1.3)

        XCTAssertGreaterThan(ttsCCR, 0, "CCR TTS should be positive after 40m/30min")

        // Verify matches sum of CCR deco stops
        let ccrDeco = try engine.calculateCCRDecoStops(
            gfLow: 0.3, gfHigh: 0.7, currentDepth: 40, diluent: diluent, setpoint: 1.3,
            config: .default)
        let manualTTS = ccrDeco.reduce(0) { $0 + $1.time }
        XCTAssertEqual(ttsCCR, manualTTS, accuracy: 0.01, "CCR TTS should match deco segments")

        print("\n=== CCR TTS (40m/30min) ===")
        print("CCR TTS: \(String(format: "%.1f", ttsCCR)) min")
    }
}
