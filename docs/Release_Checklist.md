# PathStitcher: release checklist

Notes on what is needed before submitting PathStitcher as a Godot addon (Asset Library or GitHub release).

## Can an addon be a new node?

Yes. `PathStitcher` has `class_name PathStitcher` and `extends Node3D`, so it already appears in the Add Node dialog. `PathSequence`, `PathModule`, `PathMarker`, `PathGroundDraper` and the other `class_name` scripts are available the same way. No `add_custom_type()` is needed.

## Already good

- Everything lives in `addons/path_stitcher/` (about 180 KB) with a `plugin.cfg` and `plugin.gd`.
- Scripts use `@tool`, doc comments and `class_name`.
- Paths inside the addon are all `res://addons/path_stitcher/...`.

## Missing (in suggested order)

1. **LICENSE file.** Blocks submission; the Asset Library requires one. MIT is the usual choice.
2. **Rename the plugin.** `plugin.cfg` says "PathStitcher Inspector"; rename to "PathStitcher" with a description of the whole addon.
3. **Release zip contains only the addon.** The repo is a whole project (SkateOrDie scene, player, `game_params`, and third-party addons GPUTrail, sky_3d, godot_xterm, blendot, godot_live_mcp). Add a `.gitattributes` with `export-ignore` for everything except `addons/path_stitcher`, or move the test scene to a separate demo repo or `demo/` folder.
4. **README at the repo root.** What it does, install steps, quick start, screenshot or GIF, property reference. Rework `docs/PathStitcher_Spec.md`.
5. **Minimal self-contained demo scene.** Uses only the addon's own assets (a basic tower or road), so a new user can try it without the skater game.
6. **Test in a clean project.** Copy only `addons/path_stitcher`, enable it, check for missing references and editor errors on enable and disable.
7. **Version, Godot compatibility, changelog.** Pick 1.0.0, state the tested Godot version, add a changelog entry.
8. **Fresh repo for the release (optional).** Old commits still hold the 4096 px textures (about 35 MB in history).

## Smaller polish

- `path_axes_follower.gd` has no `@tool`; fine if it is runtime only, but confirm it is intended.
- Add a node icon (`@icon(...)` or an SVG) so the node looks right in the scene tree.
- Test undo/redo and save/reload of a scene using `PathStitcher`.
- Document the licence of the sample Blender block meshes and textures.
