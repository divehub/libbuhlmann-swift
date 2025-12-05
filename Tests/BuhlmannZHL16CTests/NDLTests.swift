import XCTest

@testable import BuhlmannZHL16C

final class NDLTests: XCTestCase {

    func testNDL() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues()

        // NDL at 30m with Air, GF 100/100 (pure M-value)
        // Should be around 15-25 mins.
        let ndl = engine.ndl(depth: 30.0, gas: Gas.air, gf: 1.0)
        print("NDL at 30m Air GF 1.0: \(ndl)")

        XCTAssertGreaterThan(ndl, 10)
        XCTAssertLessThan(ndl, 30)

        // With GF 0.8 (more conservative), NDL should be shorter
        let ndlConservative = engine.ndl(depth: 30.0, gas: Gas.air, gf: 0.8)
        print("NDL at 30m Air GF 0.8: \(ndlConservative)")

        XCTAssertLessThan(ndlConservative, ndl)
    }

    /// Test NDL values against known reference values
    func testNDLReferenceValues() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues()

        // Test NDL at various depths with GF 100 (pure Bühlmann)
        // These are approximate expected values from Bühlmann tables
        let testCases: [(depth: Double, minNDL: Double, maxNDL: Double)] = [
            (12.0, 140, 250),  // 12m - very long NDL
            (18.0, 50, 80),  // 18m - about 1 hour
            (24.0, 25, 40),  // 24m - about 30 mins
            (30.0, 15, 25),  // 30m - about 20 mins
            (40.0, 7, 15),  // 40m - short NDL (inclusive of 8)
        ]

        for testCase in testCases {
            var freshEngine = BuhlmannZHL16C()
            freshEngine.initializeTissues()

            let ndl = freshEngine.ndl(depth: testCase.depth, gas: Gas.air, gf: 1.0)
            XCTAssertGreaterThanOrEqual(
                ndl, testCase.minNDL, "NDL at \(testCase.depth)m should be >= \(testCase.minNDL)")
            XCTAssertLessThanOrEqual(
                ndl, testCase.maxNDL, "NDL at \(testCase.depth)m should be <= \(testCase.maxNDL)")
        }
    }

    func testNoDecoLimit() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues()

        // NDL at 30m on Air should be around 15-17 mins (depending on GF)
        // With GF 1.0 (pure M-value), it's around 16-17 mins.
        let ndl = engine.ndl(depth: 30, gas: Gas.air, gf: 1.0)

        XCTAssertGreaterThan(ndl, 10)
        XCTAssertLessThan(ndl, 25)
    }

    /// Test NDL at 30m with various gradient factors
    func testNDL_30m_VariousGF() {
        var engine = BuhlmannZHL16C()
        engine.initializeTissues()

        // NDL at 30m with different GFs
        let ndl100 = engine.ndl(depth: 30, gas: Gas.air, gf: 1.00)  // Pure Bühlmann
        let ndl85 = engine.ndl(depth: 30, gas: Gas.air, gf: 0.85)  // Common recreational
        let ndl70 = engine.ndl(depth: 30, gas: Gas.air, gf: 0.70)  // Conservative

        print("\n=== NDL at 30m ===")
        print("GF 100: \(ndl100) min")
        print("GF 85: \(ndl85) min")
        print("GF 70: \(ndl70) min")

        // Expected: Pure Bühlmann ~16-17 min, GF reduces this proportionally
        XCTAssertGreaterThan(ndl100, ndl85, "Lower GF should give shorter NDL")
        XCTAssertGreaterThan(ndl85, ndl70, "Lower GF should give shorter NDL")

        // NDL with GF 70 should be around 8-12 min
        XCTAssertGreaterThanOrEqual(ndl70, 8)
        XCTAssertLessThan(ndl70, 15)
    }
}
