# libbuhlmann-swift Engineering Context

## Project Goal
A pure Swift library implementing the Bühlmann decompression algorithm (specifically ZHL-16C) for dive planning and profile analysis.

## Core Concepts
- **Algorithm**: Bühlmann ZHL-16C (Zero-Haldane-Lucus, 16 compartments).
- **Gradient Factors**: Implements Gradient Factors (GF Low/High) for conservatism.

## Architecture
- **Type**: Swift Package.
- **Dependencies**: Minimal/None. Should remain pure Swift to ensure portability across platforms (iOS, macOS, watchOS).
- **Concurrency**: `Sendable` types where possible to support concurrent dive planning calculations.

## Development Guidelines
- **Correctness**: This is a critical safety component. Changes must be verified against known profiles or standard test cases.
- **Performance**: Calculations (like generating a deco schedule) may be run on background threads. Ensure efficiency.

## Build & Test
- **Tooling**: Use `swift test` for running unit tests.
- **UI Interaction**: None. This is a logic library.
