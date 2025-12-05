import XCTest

@testable import BuhlmannZHL16C

final class TTSBailoutTests: XCTestCase {

    // MARK: - Time To Surface (TTS) Tests

    /// Test OC Time To Surface calculation
    func testTimeToSurface_OC() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: .air)

        // Dive to 30m for 25 minutes - should require deco
        engine.addSegment(startDepth: 0, endDepth: 30, time: 3, gas: .air)
        engine.addSegment(startDepth: 30, endDepth: 30, time: 25, gas: .air)

        let tts = engine.timeToSurface(
            gfLow: 0.3, gfHigh: 0.7, currentDepth: 30, bottomGas: .air)

        // TTS should be positive (some deco required)
        XCTAssertGreaterThan(tts, 0, "TTS should be positive after 30m/25min")

        // Verify TTS matches manual calculation
        let decoStops = engine.calculateDecoStops(
            gfLow: 0.3, gfHigh: 0.7, currentDepth: 30, gas: .air)
        let manualTTS = decoStops.reduce(0) { $0 + $1.time }
        XCTAssertEqual(tts, manualTTS, accuracy: 0.01, "TTS should match sum of deco segments")

        print("\n=== OC TTS (30m/25min Air) ===")
        print("TTS: \(String(format: "%.1f", tts)) min")
    }

    /// Test TTS with no deco required
    func testTimeToSurface_NoDeco() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: .air)

        // Short dive within NDL
        engine.addSegment(startDepth: 0, endDepth: 20, time: 2, gas: .air)
        engine.addSegment(startDepth: 20, endDepth: 20, time: 10, gas: .air)

        let tts = engine.timeToSurface(
            gfLow: 0.3, gfHigh: 0.85, currentDepth: 20, bottomGas: .air)

        // TTS should just be ascent time (20m / 9m/min ≈ 2.2 min)
        XCTAssertLessThan(tts, 5, "TTS for no-deco dive should be minimal (just ascent time)")
        XCTAssertGreaterThan(tts, 1, "TTS should include ascent time")

        print("\n=== OC TTS (20m/10min - No Deco) ===")
        print("TTS: \(String(format: "%.1f", tts)) min")
    }

    // MARK: - Bailout Planning Tests

    /// Test worst-case bailout calculation
    func testCalculateBailoutPlan() throws {
        var engine = BuhlmannZHL16C()
        let diluent = try Gas(o2: 0.21, he: 0.35)
        engine.initializeTissues(gas: diluent)

        // Plan a CCR dive: descend to 50m, stay 25 minutes
        // Now includes setpoint per segment
        let diveSegments: [(startDepth: Double, endDepth: Double, time: Double, setpoint: Double)] =
            [
                (0, 50, 5, 1.3),  // Descent at SP 1.3
                (50, 50, 25, 1.3),  // Bottom time at SP 1.3
            ]

        // Bailout gas: bottom gas is diluent, plus EAN50 for deco
        let ean50 = try Gas(o2: 0.50, he: 0.0, maxDepth: 21)

        let bailout = try engine.calculateBailoutPlan(
            diveSegments: diveSegments,
            diluent: diluent,
            bailoutDecoGases: [ean50],
            gfLow: 0.3,
            gfHigh: 0.7
        )

        // Verify worst case is at end of bottom time (max depth + longest exposure)
        XCTAssertEqual(
            bailout.worstCaseDepth, 50, accuracy: 1,
            "Worst case should be at bottom depth")
        XCTAssertGreaterThan(bailout.worstCaseTTS, 0, "Bailout TTS should be positive")
        XCTAssertGreaterThan(
            bailout.bailoutSchedule.count, 0, "Should have bailout deco schedule")

        // Verify CCR segments are included
        XCTAssertEqual(
            bailout.ccrSegmentsToWorstCase.count, 2,
            "Should have 2 CCR segments (descent + bottom)")

        print("\n=== Bailout Analysis (50m/25min CCR) ===")
        print("Worst-case depth: \(Int(bailout.worstCaseDepth))m")
        print("Worst-case TTS: \(String(format: "%.1f", bailout.worstCaseTTS)) min")
        print("CCR segments to bailout point: \(bailout.ccrSegmentsToWorstCase.count)")
        print("Bailout schedule:")
        for segment in bailout.bailoutSchedule where segment.startDepth == segment.endDepth {
            print(
                "  \(Int(segment.startDepth))m: \(Int(segment.time)) min (\(String(format: "%.0f%%", segment.gas.o2 * 100)) O2)"
            )
        }
    }

    /// Test bailout from current state
    func testCalculateBailoutFromCurrentState() throws {
        var engine = BuhlmannZHL16C()
        let diluent = try Gas(o2: 0.21, he: 0.35)
        engine.initializeTissues(gas: diluent)

        // Simulate CCR dive to 40m for 20 minutes
        try engine.addCCRSegment(
            startDepth: 0, endDepth: 40, time: 4, diluent: diluent, setpoint: 1.3)
        try engine.addCCRSegment(
            startDepth: 40, endDepth: 40, time: 20, diluent: diluent, setpoint: 1.3)

        // Calculate OC bailout from current state
        let bailoutSchedule = engine.calculateBailoutFromCurrentState(
            currentDepth: 40,
            bailoutGas: diluent,
            bailoutDecoGases: [],
            gfLow: 0.3,
            gfHigh: 0.7
        )

        let bailoutTTS = bailoutSchedule.reduce(0) { $0 + $1.time }

        // Compare with continuing on CCR
        let ccrTTS = try engine.timeToSurfaceCCR(
            gfLow: 0.3, gfHigh: 0.7, currentDepth: 40, diluent: diluent, setpoint: 1.3)

        print("\n=== Bailout vs CCR TTS Comparison (40m/20min) ===")
        print("OC Bailout TTS: \(String(format: "%.1f", bailoutTTS)) min")
        print("CCR Continue TTS: \(String(format: "%.1f", ccrTTS)) min")

        // OC bailout should take longer than continuing on CCR (lower O2 fraction)
        XCTAssertGreaterThan(
            bailoutTTS, ccrTTS,
            "OC bailout should have longer TTS than continuing on CCR")
    }

    /// Test bailout with deco gases reduces TTS
    func testBailoutWithDecoGases() throws {
        var engine = BuhlmannZHL16C()
        let diluent = try Gas(o2: 0.21, he: 0.35)
        engine.initializeTissues(gas: diluent)

        // CCR dive: 45m for 25 minutes
        try engine.addCCRSegment(
            startDepth: 0, endDepth: 45, time: 4.5, diluent: diluent, setpoint: 1.3)
        try engine.addCCRSegment(
            startDepth: 45, endDepth: 45, time: 25, diluent: diluent, setpoint: 1.3)

        // Bailout without deco gases
        let bailoutNoGas = engine.calculateBailoutFromCurrentState(
            currentDepth: 45,
            bailoutGas: diluent,
            bailoutDecoGases: [],
            gfLow: 0.3,
            gfHigh: 0.7
        )
        let ttsNoGas = bailoutNoGas.reduce(0) { $0 + $1.time }

        // Bailout with deco gases
        let ean50 = try! Gas(o2: 0.50, he: 0.0, maxDepth: 21)
        let o2 = try! Gas(o2: 1.0, he: 0.0, maxDepth: 6)

        let bailoutWithGas = engine.calculateBailoutFromCurrentState(
            currentDepth: 45,
            bailoutGas: diluent,
            bailoutDecoGases: [ean50, o2],
            gfLow: 0.3,
            gfHigh: 0.7
        )
        let ttsWithGas = bailoutWithGas.reduce(0) { $0 + $1.time }

        print("\n=== Bailout Gas Comparison (45m/25min CCR) ===")
        print("Bailout TTS (no deco gas): \(String(format: "%.1f", ttsNoGas)) min")
        print("Bailout TTS (EAN50 + O2): \(String(format: "%.1f", ttsWithGas)) min")

        // Having deco gases should reduce TTS
        XCTAssertLessThan(
            ttsWithGas, ttsNoGas,
            "Bailout with deco gases should have shorter TTS")
    }
}
