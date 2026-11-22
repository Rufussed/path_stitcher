# Changelog

All notable changes to PathStitcher. Versions follow [Semantic Versioning](https://semver.org/).

## 1.0.0 - 2026-11-22

First public release. Tested with Godot 4.7.2 on Linux.

### Added

- `PathStitcher` node: lays modular building blocks along a `Path3D`, wedging and shearing each block so neighbouring seams meet exactly. Linear bend (GPU-instanced) and Full bend (per-vertex, CPU-merged); World and Path up modes; Flip Side; `Col-` and `ColVis-` collision generation.
- BUILDING BLOCKS Inspector section: sections laid end to end, each with its own length and, in it, a first and last block with counts, a reorderable pattern or seeded random sequence, fit modes, per-block length, overlap, stretch and offsets, and markers.
- `PathSection`, `PathModule`, `PathPatternEntry` and `PathMarkerEntry` resources; `PathMarker` node.
- `PathSpiral`: a `Path3D` that builds a spiral curve from Inspector settings (turns, start and end radius, rise per turn, points per turn, anticlockwise or clockwise direction), rebuilding live. Optional; any `Path3D` works with a `PathStitcher`.
- Blocks are never mirrored by default: X runs along the path, Y is up and +Z is the path's right, a plain rotation of the block as authored. `flip_side` mirrors it so +Z faces the left. `PathSpiral` and `PathCircle` run anticlockwise seen from above, so +Z faces outwards.
- `PathCircle`: a `Path3D` that builds a flat circle from a single radius setting.
- `PathGroundDraper`: drapes a path onto physics collision and banks it to the ground.
- `PathAxesFollower`: supplies forward and right movement axes from the nearest path.
- MIT licence, README and a demo project (`demo/tower_demo.tscn`, a Tower of Babel built from two blocks).

### Fixed (during release preparation)

- Blocks made of primitive meshes (`BoxMesh`, `CylinderMesh`, ...) built nothing, because `surface_get_primitive_type()` only exists on `ArrayMesh`.
- Blocks with single-sided materials rendered inside out: triangle winding was reversed only when Flip Side was on, but the default mapping is the mirror. Double-sided materials had hidden this.
- `PathAxesFollower` referenced a project-specific `GameParams` class and failed to load in any other project; it now exposes its tuning as plain properties.
