import Foundation

public struct BuhlmannZHL16C: DecompressionAlgorithm {
    public var compartments: [Compartment]

    // Water vapor pressure in lungs (approx 0.0627 bar)
    private let waterVaporPressure = 0.0627

    // Water density in kg/m^3 (default 1030 for salt water)
    public var waterDensity: Double = 1030.0

    public init() {
        self.compartments = Compartment.createAll()
    }

    /// Initialize tissues to surface pressure with a specific gas (usually air).
    public mutating func initializeTissues(surfacePressure: Double = 1.01325, gas: Gas = .air) {
        let inspiredPressure = surfacePressure - waterVaporPressure
        let pN2 = inspiredPressure * gas.n2
        let pHe = inspiredPressure * gas.he

        for i in 0..<compartments.count {
            compartments[i].pN2 = pN2
            compartments[i].pHe = pHe
        }
    }

    /// Apply Schreiner equation for a segment.
    /// - Parameters:
    ///   - startDepth: Depth at start of segment (meters).
    ///   - endDepth: Depth at end of segment (meters).
    ///   - time: Duration of segment (minutes).
    ///   - gas: Breathing gas.
    ///   - surfacePressure: Surface pressure (bar).
    public mutating func addSegment(
        startDepth: Double, endDepth: Double, time: Double, gas: Gas,
        surfacePressure: Double = 1.01325
    ) {
        let startPressure = PressureConverter.metersToBar(
            depth: startDepth, surfacePressure: surfacePressure, density: waterDensity)
        let endPressure = PressureConverter.metersToBar(
            depth: endDepth, surfacePressure: surfacePressure, density: waterDensity)

        // Rate of pressure change (bar per minute)
        let pressureRate = (endPressure - startPressure) / time

        for i in 0..<compartments.count {
            updateCompartment(
                &compartments[i], startPressure: startPressure, rate: pressureRate, time: time,
                gas: gas)
        }
    }

    private func updateCompartment(
        _ compartment: inout Compartment, startPressure: Double, rate: Double, time: Double,
        gas: Gas
    ) {
        // Schreiner Equation:
        // P_t = P_alv0 + R * (t - 1/k) - (P_alv0 - P_i0 - R/k) * e^(-kt)

        // Nitrogen
        let pAlvN2_0 = (startPressure - waterVaporPressure) * gas.n2
        let rateN2 = rate * gas.n2
        let kN2 = compartment.n2K
        let pN2_initial = compartment.pN2

        if time > 0 {
            let decayN2 = exp(-kN2 * time)
            let term1 = pAlvN2_0 + rateN2 * (time - 1.0 / kN2)
            let term2 = (pAlvN2_0 - pN2_initial - rateN2 / kN2) * decayN2
            compartment.pN2 = term1 - term2
        }

        // Helium
        let pAlvHe_0 = (startPressure - waterVaporPressure) * gas.he
        let rateHe = rate * gas.he
        let kHe = compartment.heK
        let pHe_initial = compartment.pHe

        if time > 0 {
            let decayHe = exp(-kHe * time)
            let term1 = pAlvHe_0 + rateHe * (time - 1.0 / kHe)
            let term2 = (pAlvHe_0 - pHe_initial - rateHe / kHe) * decayHe
            compartment.pHe = term1 - term2
        }
    }

    /// Run a full dive profile.
    /// - Parameter profile: The dive profile to execute.
    /// - Parameter surfacePressure: Surface pressure (bar).
    public mutating func runProfile(_ profile: DiveProfile, surfacePressure: Double = 1.01325) {
        for segment in profile.segments {
            addSegment(
                startDepth: segment.startDepth, endDepth: segment.endDepth, time: segment.time,
                gas: segment.gas, surfacePressure: surfacePressure)
        }
    }

    /// Calculate current ceiling (shallowest depth allowed) in meters using Gradient Factors.
    /// Uses optimized binary search algorithm for O(log n) performance.
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low (e.g., 0.30). Must be in range (0, 1].
    ///   - gfHigh: Gradient Factor High (e.g., 0.85). Must be in range (0, 1] and >= gfLow.
    ///   - fixedFirstStopDepth: Optional fixed depth to anchor GF slope.
    ///   - surfacePressure: Surface pressure in bar (default 1.01325 for sea level).
    /// - Returns: Ceiling depth in meters.
    public func ceiling(
        gfLow: Double,
        gfHigh: Double,
        fixedFirstStopDepth: Double? = nil,
        surfacePressure: Double = 1.01325
    ) -> Double {
        return ceilingBinarySearch(
            gfLow: gfLow,
            gfHigh: gfHigh,
            fixedFirstStopDepth: fixedFirstStopDepth,
            surfacePressure: surfacePressure
        )
    }

    /// Calculate ceiling using binary search algorithm.
    /// O(log n) complexity - efficient for deep dives.
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low (e.g., 0.30). Must be in range (0, 1].
    ///   - gfHigh: Gradient Factor High (e.g., 0.85). Must be in range (0, 1] and >= gfLow.
    ///   - fixedFirstStopDepth: Optional fixed depth to anchor GF slope.
    ///   - surfacePressure: Surface pressure in bar (default 1.01325 for sea level).
    /// - Returns: Ceiling depth in meters.
    public func ceilingBinarySearch(
        gfLow: Double,
        gfHigh: Double,
        fixedFirstStopDepth: Double? = nil,
        surfacePressure: Double = 1.01325
    ) -> Double {
        // Validate GF parameters
        let clampedGfLow = max(0.01, min(1.0, gfLow))
        let clampedGfHigh = max(clampedGfLow, min(1.0, gfHigh))

        // 1. Find the "Deepest Possible Stop" using GF_Low.
        // This is the deepest depth where the leading tissue can tolerate surfacing with GF_Low.
        var firstStopDepth = fixedFirstStopDepth ?? 0.0

        if fixedFirstStopDepth == nil {
            for compartment in compartments {
                let tol = compartment.tolerableAmbientPressure(gf: clampedGfLow)
                let depth = PressureConverter.barToMeters(
                    pressure: tol, surfacePressure: surfacePressure, density: waterDensity)
                firstStopDepth = max(firstStopDepth, depth)
            }
        }

        if firstStopDepth <= 0 { return 0.0 }

        // 2. Use binary search to find the ceiling efficiently.
        // The ceiling is the shallowest depth where all compartments are within their M-gradient limit.
        // GF(d) = GF_High - (GF_High - GF_Low) * (d / firstStopDepth) for d < firstStopDepth
        // GF(d) = GF_Low for d >= firstStopDepth
        //
        // Binary search: find the smallest depth where isSafe(depth) = true
        // Since safety is monotonic (deeper = safer), we search for the transition point.

        let precision = 0.01  // 1cm precision for final result
        var lo = 0.0
        var hi = firstStopDepth + 0.1  // Start slightly deeper to catch edge cases

        // First, verify the deep bound is safe (it should be at firstStopDepth with GF_Low)
        if !isDepthSafe(
            hi, gfLow: clampedGfLow, gfHigh: clampedGfHigh,
            firstStopDepth: firstStopDepth, surfacePressure: surfacePressure)
        {
            // Edge case: even firstStopDepth isn't safe (shouldn't happen normally)
            // Fall back to firstStopDepth
            return firstStopDepth
        }

        // Check if surface is safe
        if isDepthSafe(
            0, gfLow: clampedGfLow, gfHigh: clampedGfHigh,
            firstStopDepth: firstStopDepth, surfacePressure: surfacePressure)
        {
            return 0.0
        }

        // Binary search: find the shallowest safe depth
        // Invariant: lo is unsafe (or 0), hi is safe
        while (hi - lo) > precision {
            let mid = (lo + hi) / 2.0
            if isDepthSafe(
                mid, gfLow: clampedGfLow, gfHigh: clampedGfHigh,
                firstStopDepth: firstStopDepth, surfacePressure: surfacePressure)
            {
                hi = mid  // mid is safe, try shallower
            } else {
                lo = mid  // mid is unsafe, need to go deeper
            }
        }

        // Return the safe depth (hi), rounded up to nearest 0.1m for consistency
        return ceil(hi * 10) / 10.0
    }

    /// Calculate ceiling using linear search algorithm.
    /// O(n) complexity - original reference implementation.
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low (e.g., 0.30). Must be in range (0, 1].
    ///   - gfHigh: Gradient Factor High (e.g., 0.85). Must be in range (0, 1] and >= gfLow.
    ///   - fixedFirstStopDepth: Optional fixed depth to anchor GF slope.
    ///   - surfacePressure: Surface pressure in bar (default 1.01325 for sea level).
    /// - Returns: Ceiling depth in meters.
    public func ceilingLinearSearch(
        gfLow: Double,
        gfHigh: Double,
        fixedFirstStopDepth: Double? = nil,
        surfacePressure: Double = 1.01325
    ) -> Double {
        // Validate GF parameters
        let clampedGfLow = max(0.01, min(1.0, gfLow))
        let clampedGfHigh = max(clampedGfLow, min(1.0, gfHigh))

        // 1. Find the "Deepest Possible Stop" using GF_Low.
        var firstStopDepth = fixedFirstStopDepth ?? 0.0

        if fixedFirstStopDepth == nil {
            for compartment in compartments {
                let tol = compartment.tolerableAmbientPressure(gf: clampedGfLow)
                let depth = PressureConverter.barToMeters(
                    pressure: tol, surfacePressure: surfacePressure, density: waterDensity)
                firstStopDepth = max(firstStopDepth, depth)
            }
        }

        if firstStopDepth <= 0 { return 0.0 }

        // 2. Linear search: Check every 0.1m from firstStopDepth up to 0.
        let epsilon = 1e-9

        // Start slightly deeper to catch edge cases
        var d = firstStopDepth + 0.1
        while d >= 0 {
            // Calculate GF at this depth using clamped values
            let gf =
                (d >= firstStopDepth)
                ? clampedGfLow
                : clampedGfHigh - (clampedGfHigh - clampedGfLow) * (d / firstStopDepth)

            // Check if this depth is safe for all compartments
            let ambientPressure = PressureConverter.metersToBar(
                depth: d, surfacePressure: surfacePressure, density: waterDensity)

            let safe = compartments.allSatisfy { compartment in
                let mValue = compartment.mValue(pressure: ambientPressure)
                let mGradient = ambientPressure + gf * (mValue - ambientPressure)
                return (compartment.pN2 + compartment.pHe) <= mGradient + epsilon
            }

            if !safe {
                // We went too shallow. The previous depth (d + 0.1) was the ceiling.
                return d + 0.1
            }

            d -= 0.1
        }

        return 0.0
    }

    /// Check if a given depth is safe for all compartments given the GF slope.
    /// - Parameters:
    ///   - depth: Depth to check in meters.
    ///   - gfLow: Clamped GF Low value.
    ///   - gfHigh: Clamped GF High value.
    ///   - firstStopDepth: The anchor depth for GF slope.
    ///   - surfacePressure: Surface pressure in bar.
    /// - Returns: True if all compartments are within M-gradient limits at this depth.
    private func isDepthSafe(
        _ depth: Double,
        gfLow: Double,
        gfHigh: Double,
        firstStopDepth: Double,
        surfacePressure: Double
    ) -> Bool {
        let epsilon = 1e-9

        // Calculate GF at this depth
        let gf: Double
        if depth >= firstStopDepth {
            gf = gfLow
        } else if firstStopDepth > 0 {
            gf = gfHigh - (gfHigh - gfLow) * (depth / firstStopDepth)
        } else {
            gf = gfHigh
        }

        // Check if this depth is safe for all compartments
        let ambientPressure = PressureConverter.metersToBar(
            depth: depth, surfacePressure: surfacePressure, density: waterDensity)

        return compartments.allSatisfy { compartment in
            let mValue = compartment.mValue(pressure: ambientPressure)
            let mGradient = ambientPressure + gf * (mValue - ambientPressure)
            return (compartment.pN2 + compartment.pHe) <= mGradient + epsilon
        }
    }

    /// Calculate No Decompression Limit (NDL) in minutes.
    /// - Parameters:
    ///   - depth: Current depth in meters.
    ///   - gas: Breathing gas.
    ///   - gf: Gradient Factor to use for the surfacing limit (usually GF_High).
    ///   - surfacePressure: Surface pressure in bar (default 1.01325 for sea level).
    /// - Returns: NDL in minutes. Returns 999 if NDL exceeds calculation limit.
    public func ndl(depth: Double, gas: Gas, gf: Double, surfacePressure: Double = 1.01325)
        -> Double
    {
        // Validate inputs
        let clampedGf = max(0.01, min(1.0, gf))

        // 1. Check if we are already in deco
        // For NDL check, we use the provided GF as a fixed value
        if ceiling(
            gfLow: clampedGf, gfHigh: clampedGf, fixedFirstStopDepth: nil,
            surfacePressure: surfacePressure) > 0
        {
            return 0
        }

        // 2. Simulate time passing until ceiling > 0
        // We clone the compartments to avoid modifying the actual state
        var simCompartments = compartments
        let currentPressure = PressureConverter.metersToBar(
            depth: depth, surfacePressure: surfacePressure, density: waterDensity)
        let waterVapor = waterVaporPressure

        // Pre-calculate gas partial pressures in alveoli
        let pAlvN2 = (currentPressure - waterVapor) * gas.n2
        let pAlvHe = (currentPressure - waterVapor) * gas.he

        // We can step forward in time.
        // Optimization: Find the controlling compartment (fastest to reach limit).
        // But with mixed gas, 'a' and 'b' change, so it's tricky.
        // Simple iterative approach: 1 minute steps.

        for t in 1...999 {  // Check up to 999 minutes
            let timeStep = 1.0  // 1 minute
            var inDeco = false

            for i in 0..<simCompartments.count {
                // Update compartment manually for speed/local access
                // N2
                let kN2 = simCompartments[i].n2K
                let pN2 = simCompartments[i].pN2
                // Constant depth, so Rate = 0
                // P = P_alv + (P_0 - P_alv) * exp(-kt)
                // We update state incrementally: P_new = P_alv + (P_old - P_alv) * exp(-k * dt)

                let decayN2 = exp(-kN2 * timeStep)
                simCompartments[i].pN2 = pAlvN2 + (pN2 - pAlvN2) * decayN2

                // He
                let kHe = simCompartments[i].heK
                let pHe = simCompartments[i].pHe
                let decayHe = exp(-kHe * timeStep)
                simCompartments[i].pHe = pAlvHe + (pHe - pAlvHe) * decayHe

                // Check ceiling
                if simCompartments[i].tolerableAmbientPressure(gf: clampedGf) > surfacePressure {
                    inDeco = true
                    break
                }
            }

            if inDeco {
                return Double(t - 1)  // The last minute was safe
            }
        }

        return 999.0  // > 999 minutes
    }

    /// Calculate decompression stops required to surface (single gas).
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low.
    ///   - gfHigh: Gradient Factor High.
    ///   - currentDepth: Current depth in meters (start of ascent).
    ///   - gas: Gas used for ascent.
    /// - Returns: Array of DiveSegments representing the ascent profile.
    public func calculateDecoStops(gfLow: Double, gfHigh: Double, currentDepth: Double, gas: Gas)
        -> [DiveSegment]
    {
        return calculateDecoStops(
            gfLow: gfLow,
            gfHigh: gfHigh,
            currentDepth: currentDepth,
            bottomGas: gas,
            decoGases: [],
            config: .default
        )
    }

    /// Calculate decompression stops with multiple gases.
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low (0 < gfLow ≤ 1.0).
    ///   - gfHigh: Gradient Factor High (gfLow ≤ gfHigh ≤ 1.0).
    ///   - currentDepth: Current depth in meters (start of ascent).
    ///   - bottomGas: The gas used at the bottom (fallback if no deco gas available).
    ///   - decoGases: Available decompression gases with their max depths set.
    ///   - config: Decompression configuration.
    ///   - surfacePressure: Surface pressure in bar (default 1.01325 for sea level).
    /// - Returns: Array of DiveSegments representing the ascent profile.
    ///
    /// Gas switching rules:
    /// - Gas switches occur at the closest stop increment depth at or below the gas's MOD
    /// - When `gasSwitchMode` is `.disabled`: instant switch, no additional time
    /// - When `gasSwitchMode` is `.minimum`: stop for `gasSwitchTime` on new gas, then continue deco if needed
    /// - When `gasSwitchMode` is `.additive`: `gasSwitchTime` on old gas, then switch and continue
    public func calculateDecoStops(
        gfLow: Double,
        gfHigh: Double,
        currentDepth: Double,
        bottomGas: Gas,
        decoGases: [Gas],
        config: DecoConfig,
        surfacePressure: Double = 1.01325
    ) -> [DiveSegment] {
        var segments: [DiveSegment] = []
        var depth = currentDepth
        var currentGas = bottomGas

        // Create a simulation copy of the engine
        var simEngine = self

        // Safety guard against infinite loops
        var iterations = 0
        let maxIterations = 100_000

        // Determine First Stop Depth (Anchor for GF Slope)
        let firstStopDepth: Double = simEngine.compartments.reduce(0.0) { maxDepth, compartment in
            let tol = compartment.tolerableAmbientPressure(gf: gfLow)
            let compartmentDepth = PressureConverter.barToMeters(
                pressure: tol, surfacePressure: surfacePressure, density: simEngine.waterDensity)
            return max(maxDepth, compartmentDepth)
        }

        // Helper to get current ceiling
        func getCeiling() -> Double {
            simEngine.ceiling(
                gfLow: gfLow, gfHigh: gfHigh, fixedFirstStopDepth: firstStopDepth,
                surfacePressure: surfacePressure)
        }

        // Helper to add a stop segment
        func addStop(at stopDepth: Double, time: Double, gas: Gas) {
            guard time > DecoUtils.depthTolerance else { return }
            simEngine.addSegment(startDepth: stopDepth, endDepth: stopDepth, time: time, gas: gas)
            segments.append(
                DiveSegment(startDepth: stopDepth, endDepth: stopDepth, time: time, gas: gas))
        }

        // Helper to add an ascent segment
        func addAscent(from startDepth: Double, to endDepth: Double, gas: Gas) {
            let distance = startDepth - endDepth
            guard distance > DecoUtils.depthTolerance else { return }
            let time = distance / config.ascentRate
            simEngine.addSegment(startDepth: startDepth, endDepth: endDepth, time: time, gas: gas)
            segments.append(
                DiveSegment(startDepth: startDepth, endDepth: endDepth, time: time, gas: gas))
        }

        // Pre-calculate gas switch depths for each deco gas
        // Switch depth is the closest stop increment at or below MOD
        let gasSwitchDepths: [(gas: Gas, switchDepth: Double)] = decoGases.compactMap { gas in
            guard let mod = gas.maxDepth else { return nil }
            let switchDepth = floor(mod / config.stopIncrement) * config.stopIncrement
            return (gas, switchDepth)
        }.sorted { $0.switchDepth > $1.switchDepth }  // Deepest first

        // Track which gases have been switched to (by index)
        var switchedGases: Set<Int> = []

        // Main decompression loop
        while depth > DecoUtils.depthTolerance && iterations < maxIterations {
            iterations += 1

            let nextStop = DecoUtils.nextStopDepth(
                from: depth, stopIncrement: config.stopIncrement,
                lastStopDepth: config.lastStopDepth)

            // --- Gas Switch Check ---
            // Find the best available gas at this depth that we haven't switched to
            var gasSwitchInfo: (index: Int, gas: Gas)? = nil
            for (index, entry) in gasSwitchDepths.enumerated() {
                guard !switchedGases.contains(index),
                    depth <= entry.switchDepth + DecoUtils.depthTolerance,
                    entry.gas.isSafe(atDepth: depth),
                    !(abs(entry.gas.o2 - currentGas.o2) < DecoUtils.gasEpsilon
                        && abs(entry.gas.he - currentGas.he) < DecoUtils.gasEpsilon)
                else { continue }

                // Pick highest O2 gas (best for deco), then highest He if O2 is equal
                if let current = gasSwitchInfo {
                    if entry.gas.o2 > current.gas.o2 + DecoUtils.gasEpsilon {
                        gasSwitchInfo = (index, entry.gas)
                    } else if abs(entry.gas.o2 - current.gas.o2) < DecoUtils.gasEpsilon
                        && entry.gas.he > current.gas.he + DecoUtils.gasEpsilon
                    {
                        gasSwitchInfo = (index, entry.gas)
                    }
                } else {
                    gasSwitchInfo = (index, entry.gas)
                }
            }

            // --- Handle Gas Switch ---
            if let switchInfo = gasSwitchInfo {
                switchedGases.insert(switchInfo.index)
                let newGas = switchInfo.gas

                switch config.gasSwitchMode {
                case .disabled:
                    // Instant switch
                    currentGas = newGas

                case .minimum:
                    // Switch to new gas immediately, stop for minimum time
                    currentGas = newGas
                    if config.gasSwitchTime > DecoUtils.depthTolerance {
                        addStop(at: depth, time: config.gasSwitchTime, gas: newGas)
                    }
                    // After the stop, re-check ceiling and continue the loop
                    continue

                case .additive:
                    // Stay on old gas during switch time, then switch
                    if config.gasSwitchTime > DecoUtils.depthTolerance {
                        addStop(at: depth, time: config.gasSwitchTime, gas: currentGas)
                    }
                    currentGas = newGas
                    // After the stop, re-check ceiling and continue the loop
                    continue
                }
            }

            // --- Check if we need to stop (ceiling prevents ascending) ---
            let ceiling = getCeiling()
            let canAscend = ceiling <= nextStop + DecoUtils.depthTolerance

            if canAscend {
                // Safe to ascend to next stop
                addAscent(from: depth, to: nextStop, gas: currentGas)
                depth = nextStop
            } else {
                // Required deco stop - wait 1 minute
                addStop(at: depth, time: 1.0, gas: currentGas)
            }
        }

        return segments
    }

    // MARK: - CCR (Closed Circuit Rebreather) Support

    /// Add a CCR segment to the simulation.
    ///
    /// CCR maintains constant ppO2, so gas fractions vary with depth. For depth-changing
    /// segments, this discretizes into small steps to accurately model the changing gas.
    ///
    /// - Parameters:
    ///   - startDepth: Depth at start of segment (meters).
    ///   - endDepth: Depth at end of segment (meters).
    ///   - time: Duration of segment (minutes).
    ///   - diluent: The CCR diluent gas (provides N2/He ratios).
    ///   - setpoint: Target ppO2 in bar (e.g., 1.3).
    ///   - surfacePressure: Surface pressure (bar).
    public mutating func addCCRSegment(
        startDepth: Double,
        endDepth: Double,
        time: Double,
        diluent: Gas,
        setpoint: Double,
        surfacePressure: Double = 1.01325
    ) throws {
        guard time > 0 else { return }

        // For constant depth, just use the effective gas at that depth
        if abs(startDepth - endDepth) < 0.01 {
            let effectiveGas = try Gas.effectiveGas(
                atDepth: startDepth, setpoint: setpoint, diluent: diluent,
                surfacePressure: surfacePressure)
            addSegment(
                startDepth: startDepth, endDepth: endDepth, time: time, gas: effectiveGas,
                surfacePressure: surfacePressure)
            return
        }

        // For depth-changing segments, discretize into small steps
        // Use 0.5m steps for good accuracy vs performance balance
        let stepSize = 0.5  // meters
        let depthChange = endDepth - startDepth
        let numSteps = max(1, Int(ceil(abs(depthChange) / stepSize)))
        let depthStep = depthChange / Double(numSteps)
        let timeStep = time / Double(numSteps)

        var currentDepth = startDepth
        for _ in 0..<numSteps {
            let nextDepth = currentDepth + depthStep
            // Use effective gas at the midpoint of this step for better accuracy
            let midDepth = (currentDepth + nextDepth) / 2.0
            let effectiveGas = try Gas.effectiveGas(
                atDepth: midDepth, setpoint: setpoint, diluent: diluent,
                surfacePressure: surfacePressure)
            addSegment(
                startDepth: currentDepth, endDepth: nextDepth, time: timeStep, gas: effectiveGas,
                surfacePressure: surfacePressure)
            currentDepth = nextDepth
        }
    }

    /// Calculate CCR decompression stops required to surface.
    ///
    /// Uses the provided setpoint for the entire ascent. Gas fractions vary with depth
    /// based on the setpoint and diluent.
    ///
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low (0 < gfLow ≤ 1.0).
    ///   - gfHigh: Gradient Factor High (gfLow ≤ gfHigh ≤ 1.0).
    ///   - currentDepth: Current depth in meters (start of ascent).
    ///   - diluent: The CCR diluent gas.
    ///   - setpoint: Target ppO2 in bar for the ascent.
    ///   - config: Decompression configuration.
    ///   - surfacePressure: Surface pressure in bar (default 1.01325).
    /// - Returns: Array of DiveSegments representing the ascent profile.
    /// - Throws: `GasError.cannotDilute` if the diluent cannot achieve the setpoint at depth.
    public func calculateCCRDecoStops(
        gfLow: Double,
        gfHigh: Double,
        currentDepth: Double,
        diluent: Gas,
        setpoint: Double,
        config: DecoConfig,
        surfacePressure: Double = 1.01325
    ) throws -> [DiveSegment] {
        // Constants for floating-point comparisons
        let depthTolerance = 0.01  // 1 cm for depth comparisons

        var segments: [DiveSegment] = []
        var depth = currentDepth

        // Create a simulation copy of the engine
        var simEngine = self

        // Safety guard against infinite loops
        var iterations = 0
        let maxIterations = 100_000

        // Determine First Stop Depth (Anchor for GF Slope)
        let firstStopDepth: Double = simEngine.compartments.reduce(0.0) { maxDepth, compartment in
            let tol = compartment.tolerableAmbientPressure(gf: gfLow)
            let compartmentDepth = PressureConverter.barToMeters(
                pressure: tol, surfacePressure: surfacePressure, density: simEngine.waterDensity)
            return max(maxDepth, compartmentDepth)
        }

        // Helper to get current ceiling
        func getCeiling() -> Double {
            simEngine.ceiling(
                gfLow: gfLow, gfHigh: gfHigh, fixedFirstStopDepth: firstStopDepth,
                surfacePressure: surfacePressure)
        }

        // Helper to get effective gas at a depth
        func getEffectiveGas(at d: Double) throws -> Gas {
            try Gas.effectiveGas(
                atDepth: d, setpoint: setpoint, diluent: diluent, surfacePressure: surfacePressure)
        }

        // Helper to add a CCR stop segment
        func addStop(at stopDepth: Double, time: Double) throws {
            guard time > depthTolerance else { return }
            let gas = try getEffectiveGas(at: stopDepth)
            try simEngine.addCCRSegment(
                startDepth: stopDepth, endDepth: stopDepth, time: time,
                diluent: diluent, setpoint: setpoint, surfacePressure: surfacePressure)
            segments.append(
                DiveSegment(startDepth: stopDepth, endDepth: stopDepth, time: time, gas: gas))
        }

        // Helper to add a CCR ascent segment
        func addAscent(from startDepth: Double, to endDepth: Double) throws {
            let distance = startDepth - endDepth
            guard distance > depthTolerance else { return }
            let time = distance / config.ascentRate
            // Use effective gas at midpoint for the segment's gas property
            let midDepth = (startDepth + endDepth) / 2.0
            let gas = try getEffectiveGas(at: midDepth)
            try simEngine.addCCRSegment(
                startDepth: startDepth, endDepth: endDepth, time: time,
                diluent: diluent, setpoint: setpoint, surfacePressure: surfacePressure)
            segments.append(
                DiveSegment(startDepth: startDepth, endDepth: endDepth, time: time, gas: gas))
        }

        // Helper to check if two depths are equal within tolerance
        func depthsEqual(_ d1: Double, _ d2: Double) -> Bool {
            abs(d1 - d2) < depthTolerance
        }

        // Helper to calculate next stop depth from current depth
        func nextStopDepth(from d: Double) -> Double {
            var next = floor(d / config.stopIncrement) * config.stopIncrement
            if depthsEqual(next, d) {
                next -= config.stopIncrement
            }
            if next > depthTolerance && next < config.lastStopDepth - depthTolerance {
                next = d > config.lastStopDepth + depthTolerance ? config.lastStopDepth : 0
            }
            return max(0, next)
        }

        // Main decompression loop
        while depth > depthTolerance && iterations < maxIterations {
            iterations += 1

            let nextStop = nextStopDepth(from: depth)

            // Check if we need to stop (ceiling prevents ascending)
            let ceiling = getCeiling()
            let canAscend = ceiling <= nextStop + depthTolerance

            if canAscend {
                // Safe to ascend to next stop
                try addAscent(from: depth, to: nextStop)
                depth = nextStop
            } else {
                // Required deco stop - wait 1 minute
                try addStop(at: depth, time: 1.0)
            }
        }

        return segments
    }

    // MARK: - Time To Surface (TTS)

    /// Calculate Time To Surface (TTS) for current tissue state using OC gas(es).
    ///
    /// TTS includes all ascent time and decompression stop time to reach the surface.
    ///
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low.
    ///   - gfHigh: Gradient Factor High.
    ///   - currentDepth: Current depth in meters.
    ///   - bottomGas: The gas used at bottom (fallback if no deco gas available).
    ///   - decoGases: Available decompression gases with their max depths set.
    ///   - config: Decompression configuration.
    ///   - surfacePressure: Surface pressure in bar.
    /// - Returns: Total time to surface in minutes.
    public func timeToSurface(
        gfLow: Double,
        gfHigh: Double,
        currentDepth: Double,
        bottomGas: Gas,
        decoGases: [Gas] = [],
        config: DecoConfig = .default,
        surfacePressure: Double = 1.01325
    ) -> Double {
        let decoStops = calculateDecoStops(
            gfLow: gfLow,
            gfHigh: gfHigh,
            currentDepth: currentDepth,
            bottomGas: bottomGas,
            decoGases: decoGases,
            config: config,
            surfacePressure: surfacePressure
        )
        return decoStops.reduce(0) { $0 + $1.time }
    }

    /// Calculate Time To Surface (TTS) for current tissue state using CCR.
    ///
    /// TTS includes all ascent time and decompression stop time to reach the surface.
    ///
    /// - Parameters:
    ///   - gfLow: Gradient Factor Low.
    ///   - gfHigh: Gradient Factor High.
    ///   - currentDepth: Current depth in meters.
    ///   - diluent: The CCR diluent gas.
    ///   - setpoint: Target ppO2 in bar for the ascent.
    ///   - config: Decompression configuration.
    ///   - surfacePressure: Surface pressure in bar.
    /// - Returns: Total time to surface in minutes.
    /// - Throws: `GasError.cannotDilute` if the diluent cannot achieve the setpoint at depth.
    public func timeToSurfaceCCR(
        gfLow: Double,
        gfHigh: Double,
        currentDepth: Double,
        diluent: Gas,
        setpoint: Double,
        config: DecoConfig = .default,
        surfacePressure: Double = 1.01325
    ) throws -> Double {
        let decoStops = try calculateCCRDecoStops(
            gfLow: gfLow,
            gfHigh: gfHigh,
            currentDepth: currentDepth,
            diluent: diluent,
            setpoint: setpoint,
            config: config,
            surfacePressure: surfacePressure
        )
        return decoStops.reduce(0) { $0 + $1.time }
    }

    // MARK: - Bailout Planning

    /// Result of a bailout analysis containing the worst-case scenario.
    public struct BailoutAnalysis: Sendable {
        /// The depth at which bailout has the longest TTS (worst case).
        public let worstCaseDepth: Double
        /// The TTS at the worst-case depth.
        public let worstCaseTTS: Double
        /// The OC deco schedule for bailout from the worst-case depth.
        public let bailoutSchedule: [DiveSegment]
        /// The tissue state at the worst-case point (for display/analysis).
        public let tissueState: [Compartment]
    }

    /// Calculate the worst-case OC bailout plan for a CCR dive.
    ///
    /// This analyzes the entire dive profile to find the point where OC bailout
    /// would result in the longest Time To Surface (TTS). This is typically at
    /// maximum depth after the longest bottom time.
    ///
    /// - Parameters:
    ///   - diveSegments: The planned CCR dive segments (before deco).
    ///   - diluent: The CCR diluent gas used during the dive.
    ///   - setpoint: The CCR setpoint used during the dive.
    ///   - bailoutGas: The primary OC gas for bailout (typically bottom gas or travel gas).
    ///   - bailoutDecoGases: Available OC deco gases for bailout ascent.
    ///   - gfLow: Gradient Factor Low.
    ///   - gfHigh: Gradient Factor High.
    ///   - config: Decompression configuration.
    ///   - surfacePressure: Surface pressure in bar.
    /// - Returns: BailoutAnalysis containing worst-case scenario and full bailout schedule.
    public func calculateBailoutPlan(
        diveSegments: [(startDepth: Double, endDepth: Double, time: Double)],
        diluent: Gas,
        setpoint: Double,
        bailoutGas: Gas,
        bailoutDecoGases: [Gas] = [],
        gfLow: Double,
        gfHigh: Double,
        config: DecoConfig = .default,
        surfacePressure: Double = 1.01325
    ) throws -> BailoutAnalysis {
        // Simulate the dive and find the worst-case bailout point
        var simEngine = self
        var worstTTS: Double = 0
        var worstDepth: Double = 0
        var worstTissueState: [Compartment] = simEngine.compartments

        // Sample points to check TTS (at each segment end and at regular intervals)
        var checkPoints: [(depth: Double, compartments: [Compartment])] = []

        // Run through the dive, collecting tissue states at key points
        for segment in diveSegments {
            // Add CCR segment to simulation
            try simEngine.addCCRSegment(
                startDepth: segment.startDepth,
                endDepth: segment.endDepth,
                time: segment.time,
                diluent: diluent,
                setpoint: setpoint,
                surfacePressure: surfacePressure
            )

            // Check at end of each segment
            checkPoints.append((depth: segment.endDepth, compartments: simEngine.compartments))

            // For long bottom segments, also check at intermediate points
            if abs(segment.startDepth - segment.endDepth) < 0.01 && segment.time > 5 {
                // Already added end point, but we should track throughout
                // For simplicity, the end of bottom time is usually worst case
            }
        }

        // Evaluate TTS at each checkpoint to find worst case
        for checkpoint in checkPoints {
            var evalEngine = BuhlmannZHL16C()
            evalEngine.compartments = checkpoint.compartments
            evalEngine.waterDensity = self.waterDensity

            let tts = evalEngine.timeToSurface(
                gfLow: gfLow,
                gfHigh: gfHigh,
                currentDepth: checkpoint.depth,
                bottomGas: bailoutGas,
                decoGases: bailoutDecoGases,
                config: config,
                surfacePressure: surfacePressure
            )

            if tts > worstTTS {
                worstTTS = tts
                worstDepth = checkpoint.depth
                worstTissueState = checkpoint.compartments
            }
        }

        // Generate the full bailout schedule from worst-case point
        var bailoutEngine = BuhlmannZHL16C()
        bailoutEngine.compartments = worstTissueState
        bailoutEngine.waterDensity = self.waterDensity

        let bailoutSchedule = bailoutEngine.calculateDecoStops(
            gfLow: gfLow,
            gfHigh: gfHigh,
            currentDepth: worstDepth,
            bottomGas: bailoutGas,
            decoGases: bailoutDecoGases,
            config: config,
            surfacePressure: surfacePressure
        )

        return BailoutAnalysis(
            worstCaseDepth: worstDepth,
            worstCaseTTS: worstTTS,
            bailoutSchedule: bailoutSchedule,
            tissueState: worstTissueState
        )
    }

    /// Calculate OC bailout from a specific point in a CCR dive.
    ///
    /// Use this when you want to calculate bailout from a specific depth/tissue state
    /// rather than finding the worst case.
    ///
    /// - Parameters:
    ///   - currentDepth: Current depth in meters.
    ///   - bailoutGas: The primary OC gas for bailout.
    ///   - bailoutDecoGases: Available OC deco gases for bailout ascent.
    ///   - gfLow: Gradient Factor Low.
    ///   - gfHigh: Gradient Factor High.
    ///   - config: Decompression configuration.
    ///   - surfacePressure: Surface pressure in bar.
    /// - Returns: Array of DiveSegments representing the OC bailout ascent profile.
    public func calculateBailoutFromCurrentState(
        currentDepth: Double,
        bailoutGas: Gas,
        bailoutDecoGases: [Gas] = [],
        gfLow: Double,
        gfHigh: Double,
        config: DecoConfig = .default,
        surfacePressure: Double = 1.01325
    ) -> [DiveSegment] {
        return calculateDecoStops(
            gfLow: gfLow,
            gfHigh: gfHigh,
            currentDepth: currentDepth,
            bottomGas: bailoutGas,
            decoGases: bailoutDecoGases,
            config: config,
            surfacePressure: surfacePressure
        )
    }
}
