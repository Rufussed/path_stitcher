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

## Still to do

1. **Test in a clean project.** Copy only `addons/path_stitcher` into a new project, enable and disable the plugin, and check for editor errors.
2. **Changelog.** Add `CHANGELOG.md` with the 1.0.0 entry and the tested Godot version (4.7.2).
3. **Fresh repo for the release (optional).** Old commits still hold the 4096 px textures (about 35 MB in history).

## Smaller polish

- `path_axes_follower.gd` has no `@tool`; fine if it is runtime only, but confirm it is intended.
- Add a node icon (`@icon(...)` or an SVG) so the node looks right in the scene tree.
- Test undo/redo and save/reload of a scene using `PathStitcher`.
