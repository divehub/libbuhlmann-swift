# BuhlmannZHL16C

A Swift implementation of the Bühlmann ZHL-16C decompression algorithm for dive planning applications.

Most of the code is written by AI, partially human reviewed. Use it at your own risk.

## Features

- **Bühlmann ZHL-16C Algorithm** - Full implementation of the 16-compartment decompression model
- **Gradient Factors** - Support for GF Low/High conservatism settings
- **Multi-gas Support** - Air, Nitrox, Trimix, and pure Oxygen
- **CCR Support** - Closed-Circuit Rebreather calculations with setpoint management
- **Bailout Planning** - CCR bailout to open circuit with multi-gas decompression
- **NDL Calculation** - No Decompression Limit calculations
- **Ceiling Calculation** - Real-time decompression ceiling with binary search optimization
- **Decompression Schedules** - Generate complete deco stop schedules
- **Swift 6 Ready** - Full `Sendable` conformance for safe concurrency

## Requirements

- Swift 6.0+
- iOS 17+ / macOS 15+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    package(url: "https://github.com/divehub/libbuhlmann-swift.git", from: "1.0.0")
]
```

Then add `BuhlmannZHL16C` to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["BuhlmannZHL16C"]
)
```

## Usage

### Basic NDL Calculation

```swift
import BuhlmannZHL16C

// Create an engine at sea level with air
var engine = BuhlmannZHL16C()

// Calculate NDL at 30 meters with GF High of 85%
let ndl = engine.ndl(depth: 30, gas: .air, gf: 0.85)
print("NDL at 30m: \(ndl) minutes")
```

### Dive Profile Simulation

```swift
import BuhlmannZHL16C

var engine = BuhlmannZHL16C()

// Simulate a dive: descend to 30m, stay 25 minutes, ascend
engine.addSegment(startDepth: 0, endDepth: 30, time: 1.5, gas: .air)  // Descent
engine.addSegment(startDepth: 30, endDepth: 30, time: 25, gas: .air)  // Bottom time

// Check current ceiling with GF 30/85
let ceiling = engine.ceiling(gfLow: 0.30, gfHigh: 0.85)
print("Current ceiling: \(ceiling)m")
```

### Decompression Schedule

```swift
import BuhlmannZHL16C

var engine = BuhlmannZHL16C()

// After a dive requiring deco...
engine.addSegment(startDepth: 0, endDepth: 40, time: 2, gas: .air)
engine.addSegment(startDepth: 40, endDepth: 40, time: 30, gas: .air)

// Calculate deco stops
let config = DecoConfig(ascentRate: 9.0, lastStopDepth: 3.0)
let result = try engine.calculateDecoStops(
    currentDepth: 40,
    gas: .air,
    gfLow: 0.30,
    gfHigh: 0.85,
    config: config
)

for stop in result.stops {
    print("\(stop.depth)m for \(stop.time) min")
}
print("TTS: \(result.tts) minutes")
```

### Multi-Gas Decompression

```swift
import BuhlmannZHL16C

// Define gases with MOD
let bottomGas = try! Gas(o2: 0.21, he: 0.35, maxDepth: 60)  // Trimix 21/35
let decoGas1 = try! Gas(o2: 0.50, he: 0.0, maxDepth: 21)    // EAN50
let decoGas2 = Gas.oxygen.withMaxDepth(6)                    // O2 at 6m

var engine = BuhlmannZHL16C()
engine.addSegment(startDepth: 0, endDepth: 50, time: 2.5, gas: bottomGas)
engine.addSegment(startDepth: 50, endDepth: 50, time: 20, gas: bottomGas)

let result = try engine.calculateMultiGasDecoStops(
    currentDepth: 50,
    gases: [bottomGas, decoGas1, decoGas2],
    gfLow: 0.30,
    gfHigh: 0.85,
    config: DecoConfig()
)
```

### CCR (Rebreather) Support

```swift
import BuhlmannZHL16C

let diluent = try! Gas(o2: 0.21, he: 0.35)  // Trimix diluent
let setpoint = 1.3  // ppO2 setpoint

var engine = BuhlmannZHL16C()

// Calculate effective gas at depth for CCR
let effectiveGas = Gas.effectiveGas(
    atDepth: 40,
    setpoint: setpoint,
    diluent: diluent
)

// Simulate CCR dive
engine.addSegment(startDepth: 0, endDepth: 40, time: 2, gas: effectiveGas)
```

### Custom Environment

```swift
import BuhlmannZHL16C

// Altitude dive in fresh water
let engine = BuhlmannZHL16C(
    surfacePressure: 0.85,      // ~1500m altitude
    gas: .air,
    waterDensity: 1000.0        // Fresh water
)
```

## API Reference

### Core Types

#### `BuhlmannZHL16C`

The main decompression engine implementing the ZHL-16C algorithm.

#### `Gas`

Represents a breathing gas mixture (O₂, He, N₂ fractions).

```swift
// Predefined gases
Gas.air         // 21% O2, 79% N2
Gas.oxygen      // 100% O2
Gas.ean32       // 32% O2 (Nitrox)
Gas.ean36       // 36% O2
Gas.nx50        // 50% O2

// Custom gas
let trimix = try Gas(o2: 0.18, he: 0.45)  // 18/45 Trimix
```

#### `DiveProfile` & `DiveSegment`

Represent dive profiles as a series of segments.

#### `DecoConfig`

Configuration for decompression calculations:

- `ascentRate` - Ascent rate (m/min)
- `surfaceRate` - Final ascent rate from last stop
- `stopIncrement` - Stop spacing (typically 3m)
- `lastStopDepth` - Depth of last stop (3m or 6m)
- `gasSwitchTime` - Time for gas switches
- `gasSwitchMode` - How gas switch time is applied

#### `Compartment`

Represents one of the 16 tissue compartments with N₂ and He loading.

### Key Methods

| Method                                      | Description                     |
| ------------------------------------------- | ------------------------------- |
| `addSegment(startDepth:endDepth:time:gas:)` | Simulate a dive segment         |
| `runProfile(_:)`                            | Run a complete dive profile     |
| `ceiling(gfLow:gfHigh:)`                    | Get current ceiling depth       |
| `ndl(depth:gas:gf:)`                        | Calculate no-deco limit         |
| `calculateDecoStops(...)`                   | Generate decompression schedule |
| `calculateMultiGasDecoStops(...)`           | Multi-gas deco schedule         |
| `calculateBailoutPlan(...)`                 | CCR bailout planning            |

## Algorithm Details

This implementation uses:

- **Schreiner Equation** for tissue gas loading calculations
- **Bühlmann ZHL-16C coefficients** for M-values
- **Gradient Factors** for adjustable conservatism
- **Binary search** for efficient ceiling calculations
- **Workman M-value equation**: `M = P_amb/b + a`

### Tissue Compartments

The model uses 16 tissue compartments with half-times ranging from 4 to 635 minutes for nitrogen, providing comprehensive modeling of gas uptake and elimination across different tissue types.

## Testing

Run tests with:

```bash
swift test
```

The test suite includes:

- Schreiner equation verification
- NDL calculations against reference tables
- Ceiling calculations
- Decompression schedule generation
- CCR and bailout scenarios
- Multi-gas switching

## Safety Disclaimer

⚠️ **This library is for educational and planning purposes only.**

- Never use dive planning software as your sole source for dive planning
- Always verify calculations with certified dive tables or computers
- Decompression theory involves physiological variability
- Consult qualified diving professionals for technical diving

## License

MIT License

## Acknowledgments

- Dr. Albert A. Bühlmann for the ZHL-16 decompression model
- Erik Baker for Gradient Factors methodology
