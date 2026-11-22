# Changelog

All notable changes to PathStitcher. Versions follow [Semantic Versioning](https://semver.org/).

## 1.0.0 - 2026-11-22

First public release. Tested with Godot 4.7.2 on Linux.

### Added

- `PathStitcher` node: lays modular building blocks along a `Path3D`, wedging and shearing each block so neighbouring seams meet exactly. Linear bend (GPU-instanced) and Full bend (per-vertex, CPU-merged); World and Path up modes; Flip Side; `Col-` and `ColVis-` collision generation.
- BUILDING BLOCKS Inspector section: first and last block with counts, a reorderable pattern or seeded random sequence, fit modes, per-block length, overlap, stretch and offsets, and markers.
- `PathSequence`, `PathModule`, `PathPatternEntry` and `PathMarkerEntry` resources; `PathMarker` node.
- `PathGroundDraper`: drapes a path onto physics collision and banks it to the ground.
- `PathAxesFollower`: supplies forward and right movement axes from the nearest path.
- MIT licence, README and a demo project (`demo/tower_demo.tscn`, a Tower of Babel built from two blocks).

### Fixed (during release preparation)

- Blocks made of primitive meshes (`BoxMesh`, `CylinderMesh`, ...) built nothing, because `surface_get_primitive_type()` only exists on `ArrayMesh`.
- Blocks with single-sided materials rendered inside out: triangle winding was reversed only when Flip Side was on, but the default mapping is the mirror. Double-sided materials had hidden this.
- `PathAxesFollower` referenced a project-specific `GameParams` class and failed to load in any other project; it now exposes its tuning as plain properties.
