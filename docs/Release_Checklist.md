# PathStitcher: release checklist

Notes on what is needed before submitting PathStitcher as a Godot addon (Asset Library or GitHub release).

## Can an addon be a new node?

Yes. `PathStitcher` has `class_name PathStitcher` and `extends Node3D`, so it already appears in the Add Node dialog. `PathSequence`, `PathModule`, `PathMarker`, `PathGroundDraper` and the other `class_name` scripts are available the same way. No `add_custom_type()` is needed.

## Already good

- Everything lives in `addons/path_stitcher/` (about 180 KB) with a `plugin.cfg` and `plugin.gd`.
- Scripts use `@tool`, doc comments and `class_name`.
- Paths inside the addon are all `res://addons/path_stitcher/...`.

## Done (2026-11-22)

- **LICENSE** (MIT) at the repo root and in the addon folder.
- **plugin.cfg**: renamed to "PathStitcher", version 1.0.0, whole-addon description.
- **Release zip** holds only the addon: `.gitattributes` marks everything else `export-ignore`.
- **README** at the root with a screenshot, install, quick start, efficiency notes and property reference.
- **Demo project**: the repo root is now a small Godot project with `demo/tower_demo.tscn` (a simplified Tower of Babel); SkateOrDie moved to its own repo.
- **Clean-project fixes**: the addon referenced SkateOrDie's `GameParams` (in `path_axes_follower.gd`); removed. Blocks made of PrimitiveMeshes failed; fixed. Blocks with single-sided materials rendered inside out (winding was reversed only with Flip Side, the wrong way round); fixed.

- **Clean-project test** (Godot 4.7.2): `git archive` of HEAD extracted into an empty project, plus a throwaway editor plugin that ran 33 checks, all passing: plugin enables, disables and re-enables; all eight classes register; Full and Linear builds work with and without Flip Side (triangle winding checked against a native BoxMesh); `ColVis-` collision is generated; a block with no material still builds (CPU fallback); the built output is not saved in the `.tscn`, and the scene rebuilds on open; the BUILDING BLOCKS inspector section appears; undo and redo of a property work. The addon alone opens and quits with no editor errors.

## Still to do

1. **Changelog.** Add `CHANGELOG.md` with the 1.0.0 entry and the tested Godot version (4.7.2).
2. **Fresh repo for the release (optional).** Old commits still hold the 4096 px textures (about 35 MB in history).

## Known limitations

- Linear mode only GPU-instances blocks whose materials are plain opaque `StandardMaterial3D`s. A mesh with no material, or any other material, takes the CPU-merged path: correct, just slower. (A material-less mesh could be treated as a default `StandardMaterial3D`; not done.)

## Smaller polish

- `path_axes_follower.gd` has no `@tool`; fine if it is runtime only, but confirm it is intended.
- Add a node icon (`@icon(...)` or an SVG) so the node looks right in the scene tree.
- Test undo/redo and save/reload of a scene using `PathStitcher`.
