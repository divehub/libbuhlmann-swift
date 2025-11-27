import XCTest
@testable import BuhlmannZHL16C

final class BuhlmannVerificationTests: XCTestCase {

    // MARK: - Pressure Conversion Verification
    
    func testPressureConversionStandard() {
        // EN 13319: 10m = 2.0 bar absolute (approx, depends on surface)
        // 10m salt water (1030 kg/m3)
        // P = P_surf + (1030 * 9.80665 * 10) / 100000
        // P = 1.01325 + 0.101008 = 1.114258 bar gauge -> 2.1275 bar absolute?
        // Wait, 10m depth usually means 2 bar absolute in rough calc.
        // But precisely:
        
        let depth = 10.0
        let p = PressureConverter.metersToBar(depth: depth)
        let expected = 1.01325 + (1030 * 9.80665 * 10) / 100000.0
        XCTAssertEqual(p, expected, accuracy: 0.00001)
        
        // Check if 10m is exactly 1 bar gauge (it's not with 1030 density)
        // 1 bar gauge = 100000 Pa
        // h = P / (rho * g) = 100000 / (1030 * 9.80665) = 9.901 m
        XCTAssertNotEqual(PressureConverter.barToMeters(pressure: 2.01325), 10.0, accuracy: 0.01)
    }

    // MARK: - M-Value Verification
    
    func testMValues() {
        // Check M-values for Compartment 5 (27 min)
        // a = 0.6667, b = 0.8126
        // Surface (1.01325 bar)
        // M = a + P_amb / b
        // Wait, M-value is the limit for Inert Gas Pressure.
        // The formula in code: mValue(pressure) = (pressure / b) + a
        // This calculates the ALLOWED Inert Gas Pressure given Ambient Pressure.
        // Let's check surface M-value (M_0)
        // M_0 = a + 1.01325 / b
        // For Comp 5: 0.6667 + 1.01325 / 0.8126 = 0.6667 + 1.2469 = 1.9136 bar
        
        let comp5 = Compartment.createAll()[4]
        let m0 = comp5.mValue(pressure: 1.01325)
        
        let expectedM0 = 0.6667 + (1.01325 / 0.8126)
        XCTAssertEqual(m0, expectedM0, accuracy: 0.0001)
    }
    
    // MARK: - NDL Verification
    
    func testNDL_40m_Air() {
        // 40m Air. P_amb = 1.01325 + (1030*9.81*40)/100000 = 1.01325 + 4.04 = 5.05 bar
        // P_N2_in = (5.05 - 0.0627) * 0.79 = 3.94 bar
        // NDL is when P_N2 reaches M_0 (approx, if GF=1.0)
        // Actually M_value at surface? No, NDL is when you can ascend to surface.
        // So P_N2 <= M_value(surface_pressure).
        // M_0 for fast tissues is high.
        // We need to find the limiting compartment.
        
        var engine = BuhlmannZHL16C()
        engine.initializeTissues(gas: Gas.air)
        
        // GF 1.0
        let ndl = engine.ndl(depth: 40, gas: Gas.air, gf: 1.0)
        
        // Standard tables: 40m -> 9-10 mins.
        // Let's see what we get.
        print("NDL 40m Air GF 1.0: \(ndl)")
        XCTAssertGreaterThan(ndl, 5)
        XCTAssertLessThan(ndl, 15)
    }
}
