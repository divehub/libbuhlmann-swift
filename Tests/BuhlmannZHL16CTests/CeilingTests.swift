import XCTest

@testable import BuhlmannZHL16C

final class CeilingTests: XCTestCase {

    func testCeiling() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // At surface, ceiling should be 0
        XCTAssertEqual(engine.ceiling(gfLow: 1.0, gfHigh: 1.0), 0.0)

        // Go deep and stay long -> incur deco
        // 40m for 30 mins on Air
        engine.addSegment(startDepth: 40.0, endDepth: 40.0, time: 30.0, gas: Gas.air)

        let ceilRaw = engine.ceiling(gfLow: 1.0, gfHigh: 1.0)
        print("Ceiling after 40m/30min Air (GF 1.0): \(ceilRaw)")

        XCTAssertGreaterThan(ceilRaw, 0.0)

        // With GF Low 0.3, ceiling should be deeper
        let ceilGF = engine.ceiling(gfLow: 0.3, gfHigh: 0.8)
        print("Ceiling after 40m/30min Air (GF 0.3/0.8): \(ceilGF)")

        XCTAssertGreaterThan(ceilGF, ceilRaw)
    }

    func testCeilingViolation() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)
        // 40m for 20 mins
        engine.addSegment(startDepth: 0, endDepth: 40, time: 2, gas: Gas.air)
        engine.addSegment(startDepth: 40, endDepth: 40, time: 18, gas: Gas.air)

        let gfLow = 0.50
        let gfHigh = 0.70
        let deco = engine.calculateDecoStops(
            gfLow: gfLow, gfHigh: gfHigh, currentDepth: 40, gas: Gas.air)

        // Replay the deco profile and check ceiling at each step
        var replayEngine = BuhlmannZHL16C()
        replayEngine.initializeTissues(gas: Gas.air)
        replayEngine.addSegment(startDepth: 0, endDepth: 40, time: 2, gas: Gas.air)
        replayEngine.addSegment(startDepth: 40, endDepth: 40, time: 18, gas: Gas.air)

        // We need to calculate firstStopDepth exactly as calculateDecoStops does to match GF scaling
        var firstStopDepth = 0.0
        for compartment in replayEngine.compartments {
            let tol = compartment.tolerableAmbientPressure(gf: gfLow)
            let depth = PressureConverter.barToMeters(pressure: tol)
            if depth > firstStopDepth { firstStopDepth = depth }
        }

        for segment in deco {
            replayEngine.addSegment(
                startDepth: segment.startDepth, endDepth: segment.endDepth, time: segment.time,
                gas: segment.gas)

            // Check ceiling at end of segment
            let c = replayEngine.ceiling(
                gfLow: gfLow, gfHigh: gfHigh, fixedFirstStopDepth: firstStopDepth)

            // Allow small floating point error (e.g. 0.01m)
            // Note: If segment.endDepth is 0 (surface), ceiling should be 0.
            if segment.endDepth > 0 {
                XCTAssertLessThanOrEqual(
                    c, segment.endDepth + 0.1,
                    "Ceiling violation at \(segment.endDepth)m. Ceiling: \(c)")
            }
        }
    }

    // MARK: - Binary Search vs Linear Search Comparison Tests

    /// Test that binary search and linear search produce identical results for no-deco scenarios
    func testCeilingAlgorithmsMatch_NoDeco() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // At surface with no loading, both should return 0
        let binaryCeiling = engine.ceilingBinarySearch(gfLow: 0.30, gfHigh: 0.70)
        let linearCeiling = engine.ceilingLinearSearch(gfLow: 0.30, gfHigh: 0.70)

        XCTAssertEqual(
            binaryCeiling, linearCeiling, accuracy: 0.1,
            "Binary and linear search should match for no-deco scenario")
        XCTAssertEqual(binaryCeiling, 0.0, "Should be 0 at surface with no loading")
    }

    /// Test that binary search and linear search produce identical results for light deco
    func testCeilingAlgorithmsMatch_LightDeco() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // 30m for 20 minutes - light deco obligation
        engine.addSegment(startDepth: 0, endDepth: 30, time: 1.5, gas: Gas.air)
        engine.addSegment(startDepth: 30, endDepth: 30, time: 18.5, gas: Gas.air)

        let gfPairs: [(Double, Double)] = [
            (0.30, 0.70),
            (0.50, 0.80),
            (0.30, 0.85),
            (1.0, 1.0),
        ]

        for (gfLow, gfHigh) in gfPairs {
            let binaryCeiling = engine.ceilingBinarySearch(gfLow: gfLow, gfHigh: gfHigh)
            let linearCeiling = engine.ceilingLinearSearch(gfLow: gfLow, gfHigh: gfHigh)

            XCTAssertEqual(
                binaryCeiling, linearCeiling, accuracy: 0.1,
                "Binary and linear search should match for GF \(gfLow)/\(gfHigh)")
        }
    }

    /// Test that binary search and linear search produce identical results for heavy deco
    func testCeilingAlgorithmsMatch_HeavyDeco() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // 40m for 30 minutes - significant deco obligation
        engine.addSegment(startDepth: 0, endDepth: 40, time: 2, gas: Gas.air)
        engine.addSegment(startDepth: 40, endDepth: 40, time: 28, gas: Gas.air)

        let gfPairs: [(Double, Double)] = [
            (0.30, 0.70),
            (0.50, 0.80),
            (0.30, 0.85),
        ]

        for (gfLow, gfHigh) in gfPairs {
            let binaryCeiling = engine.ceilingBinarySearch(gfLow: gfLow, gfHigh: gfHigh)
            let linearCeiling = engine.ceilingLinearSearch(gfLow: gfLow, gfHigh: gfHigh)

            XCTAssertEqual(
                binaryCeiling, linearCeiling, accuracy: 0.1,
                "Binary and linear search should match for heavy deco GF \(gfLow)/\(gfHigh). Binary: \(binaryCeiling), Linear: \(linearCeiling)"
            )
        }
    }

    /// Test that binary search and linear search produce identical results for deep trimix dives
    func testCeilingAlgorithmsMatch_DeepTrimix() {
        var engine = BuhlmannZHL16C()
        let trimix = try! Gas(o2: 0.18, he: 0.45)  // TMX 18/45
        engine.initializeTissues(gas: trimix)

        // 60m for 20 minutes - deep trimix dive
        engine.addSegment(startDepth: 0, endDepth: 60, time: 3, gas: trimix)
        engine.addSegment(startDepth: 60, endDepth: 60, time: 17, gas: trimix)

        let binaryCeiling = engine.ceilingBinarySearch(gfLow: 0.30, gfHigh: 0.85)
        let linearCeiling = engine.ceilingLinearSearch(gfLow: 0.30, gfHigh: 0.85)

        XCTAssertEqual(
            binaryCeiling, linearCeiling, accuracy: 0.1,
            "Binary and linear search should match for deep trimix. Binary: \(binaryCeiling), Linear: \(linearCeiling)"
        )
    }

    /// Test that binary search and linear search match with fixed first stop depth
    func testCeilingAlgorithmsMatch_FixedFirstStop() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // 40m for 25 minutes
        engine.addSegment(startDepth: 0, endDepth: 40, time: 2, gas: Gas.air)
        engine.addSegment(startDepth: 40, endDepth: 40, time: 23, gas: Gas.air)

        // Test with a fixed first stop depth
        let fixedFirstStop = 18.0

        let binaryCeiling = engine.ceilingBinarySearch(
            gfLow: 0.30, gfHigh: 0.70, fixedFirstStopDepth: fixedFirstStop)
        let linearCeiling = engine.ceilingLinearSearch(
            gfLow: 0.30, gfHigh: 0.70, fixedFirstStopDepth: fixedFirstStop)

        XCTAssertEqual(
            binaryCeiling, linearCeiling, accuracy: 0.1,
            "Binary and linear search should match with fixed first stop. Binary: \(binaryCeiling), Linear: \(linearCeiling)"
        )
    }

    /// Test ceiling algorithms at multiple points during ascent
    func testCeilingAlgorithmsMatch_DuringAscent() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // Build up deco obligation
        engine.addSegment(startDepth: 0, endDepth: 40, time: 2, gas: Gas.air)
        engine.addSegment(startDepth: 40, endDepth: 40, time: 20, gas: Gas.air)

        let gfLow = 0.30
        let gfHigh = 0.70

        // Simulate ascent and check at each stop
        let depths = [40.0, 30.0, 21.0, 15.0, 12.0, 9.0, 6.0, 3.0]

        for depth in depths {
            // Ascend to this depth
            if depth < 40 {
                let previousDepth = depths[depths.firstIndex(of: depth)! - 1]
                let travelTime = (previousDepth - depth) / 9.0  // 9m/min ascent
                engine.addSegment(
                    startDepth: previousDepth, endDepth: depth, time: travelTime, gas: Gas.air)
            }

            let binaryCeiling = engine.ceilingBinarySearch(gfLow: gfLow, gfHigh: gfHigh)
            let linearCeiling = engine.ceilingLinearSearch(gfLow: gfLow, gfHigh: gfHigh)

            XCTAssertEqual(
                binaryCeiling, linearCeiling, accuracy: 0.1,
                "Algorithms should match at \(depth)m. Binary: \(binaryCeiling), Linear: \(linearCeiling)"
            )

            // Add 1 minute stop if needed
            if binaryCeiling >= depth {
                engine.addSegment(startDepth: depth, endDepth: depth, time: 1, gas: Gas.air)
            }
        }
    }

    /// Performance comparison test (not a correctness test, just for observation)
    func testCeilingPerformanceComparison() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)

        // Deep dive with significant deco
        engine.addSegment(startDepth: 0, endDepth: 50, time: 2.5, gas: Gas.air)
        engine.addSegment(startDepth: 50, endDepth: 50, time: 25, gas: Gas.air)

        let iterations = 100

        // Time binary search
        let binaryStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = engine.ceilingBinarySearch(gfLow: 0.30, gfHigh: 0.70)
        }
        let binaryTime = CFAbsoluteTimeGetCurrent() - binaryStart

        // Time linear search
        let linearStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = engine.ceilingLinearSearch(gfLow: 0.30, gfHigh: 0.70)
        }
        let linearTime = CFAbsoluteTimeGetCurrent() - linearStart

        print("\n=== Ceiling Algorithm Performance (\(iterations) iterations) ===")
        print("Binary search: \(String(format: "%.4f", binaryTime * 1000))ms")
        print("Linear search: \(String(format: "%.4f", linearTime * 1000))ms")
        print("Speedup: \(String(format: "%.2f", linearTime / binaryTime))x")

        // Verify results are the same
        let binaryResult = engine.ceilingBinarySearch(gfLow: 0.30, gfHigh: 0.70)
        let linearResult = engine.ceilingLinearSearch(gfLow: 0.30, gfHigh: 0.70)
        XCTAssertEqual(binaryResult, linearResult, accuracy: 0.1)
    }

    /// Test edge case: very deep dive (100m+)
    func testCeilingAlgorithmsMatch_VeryDeepDive() {
        var engine = BuhlmannZHL16C()
        let trimix = try! Gas(o2: 0.12, he: 0.60)  // TMX 12/60 for deep diving
        engine.initializeTissues(gas: trimix)

        // 100m for 15 minutes - extreme technical dive
        engine.addSegment(startDepth: 0, endDepth: 100, time: 5, gas: trimix)
        engine.addSegment(startDepth: 100, endDepth: 100, time: 10, gas: trimix)

        let binaryCeiling = engine.ceilingBinarySearch(gfLow: 0.30, gfHigh: 0.85)
        let linearCeiling = engine.ceilingLinearSearch(gfLow: 0.30, gfHigh: 0.85)

        print("\n=== 100m Deep Dive Ceiling ===")
        print("Binary: \(binaryCeiling)m, Linear: \(linearCeiling)m")

        XCTAssertEqual(
            binaryCeiling, linearCeiling, accuracy: 0.1,
            "Binary and linear search should match for very deep dive")
        XCTAssertGreaterThan(binaryCeiling, 30, "Deep dive should have significant ceiling")
    }
}
