# PathMesh3D: Deformation & Path-Relative Movement Spec

Oct 3, 2026 · Rufus Lane · Living version: https://claude.ai/code/artifact/d2d8847d-dbfe-4105-8e40-8fb3cc5e4bfd

## Purpose and scope

The tool repeats a modular mesh along a Curve3D, deforming it so neighbouring modules meet seamlessly. It also, optionally, gives characters movement axes taken from the nearest path. Both are general-purpose Godot features. The Tower of Babel is the first test case.

- **Deformation (core):** repeat a source module every N metres, wedging it to the local curvature and shearing it to the local slope. This replaces the rigid placement that leaves gaps and lips.
- **Movement axes (optional, enabled for this test):** each path supplies forward, back, left and right vectors at the player's position. Paths can branch, and the nearest path becomes the provider. This only supplies axes; it never locks the player to the path.
- **Prototype:** a GDScript `@tool` node first. A GDExtension, and possibly a proposal to Godot core (alongside proposal #12844), comes later once the API is proven.

## Path coordinates (px, py, pz)

Positions relative to a path use path coordinates, named to match the source module axes and Godot's +Y up:

| Coord | Meaning | Matches |
| --- | --- | --- |
| `px` | Distance along the path (s); Godot's `PathFollow3D.progress` | Module X |
| `py` | Height above the path point, along world up | Module Y |
| `pz` | Horizontal sideways offset, + = left of the direction of travel | Module Z |

A path's direction is its point order: px = 0 at the first Curve3D point and increases towards the last, so +px is forward. On SpiralPath, forward is uphill.

Equivalent conventions elsewhere: Frenet / curvilinear coordinates (s, d) in robotics, station and offset (chainage) in road and rail design.

Conversion to world space, with P(s) the curve point, L(s) the horizontal left vector (Û × flattened tangent) and Û world up:

```latex
W = P(p_x) + p_z\,L(p_x) + p_y\,\hat{U}
```

The stitcher is exactly this conversion: a source vertex (x, y, z) of module i sits at path coordinates (cᵢ + x, y, z). The movement provider reports the player's (px, py, pz) through the inverse (closest offset, then height and sideways offset from that point). Example: the test player starts at (1, 0, +2.5), 1 m along the path and 2.5 m left (outward on SpiralPath).

## Source module conventions

A module is authored in Blender, imported to Godot as a `.blend`, and read in its own local space. Block1 is the reference module.

| Item | Convention | Block1 |
| --- | --- | --- |
| Along-path axis | Godot +X | X −3 to +3 m (6 m) |
| Up axis | Godot +Y | Y 0 to 16 m |
| Radial axis | Godot +Z, outward | Z −5.5 to +5.5 m (11 m) |
| Origin | Centre of X, centre of Z, floor level | Path runs through the middle of the depth |
| Spacing | Joint to joint along the path | 5 m, so 0.5 m overlap at each end |
| Blender axes | Blender Y becomes Godot Z | Blender Y = 0 is the centre |

With the origin centred on Z, the inner half (−Z) is compressed and the outer half (+Z) is expanded.

**Collision naming** (object name prefix, editable on the node):

| Prefix | Rendered | Collision | Example |
| --- | --- | --- | --- |
| `ColVis-` | Yes | Yes, trimesh | `ColVis-Floor`, `ColVis-Wall` |
| `Col-` | No | Yes, trimesh | none in Block1 yet |
| anything else | Yes | No | arches, pillars, window block |

The prefixes avoid Godot's importer suffixes (`-col`, `-colonly`), so the importer leaves the meshes alone and the tool decides.

## Deformation model

Each vertex is mapped through the curve rather than the module being moved as one rigid piece. Neighbouring modules evaluate the same curve point at their shared joint, so their seams coincide exactly.

For a source vertex (x, y, z) in module i, whose centre sits at path distance cᵢ (the middle of its two joints):

```latex
s = c_i + x \qquad V = P(s) + z\,R(s) + y\,\hat{U}
```

- **P(s):** the curve point at distance s, extended along the end tangent beyond the path ends.
- **R(s):** the horizontal lateral (outward) direction, Û × the flattened tangent.
- **Û:** world up. Walls stay vertical; the slope becomes a vertical shear, not a pitch.

**Wedge.** A vertex at radial offset z moves z × Δθ further along the path than the centre line, where Δθ is the heading change over the module. Outer faces lengthen and inner faces shorten.

**Shear.** The leading and trailing edges take the path height at their own s. Measured from the module centre, the leading edge drops by about ΔY/2 and the trailing edge rises by ΔY/2.

**Normals and tangents** are transformed by the mapping's Jacobian J = [∂V/∂x, Û, R]: normals by (J⁻¹)ᵀ, tangents by J. UVs are unchanged.

Measured on SpiralPath (5 turns, 2,750 m, radius 100 m down to 75 m, 16 m rise per turn), per 5 m module, Block1 at ±5.5 m:

| Path distance | Radius | Turn | Rise ΔY | Inner face | Outer face |
| --- | --- | --- | --- | --- | --- |
| 0 m | 100.7 m | 2.85° | 0.127 m | 4.724 m | 5.272 m |
| 1,500 m (module 300) | 87.3 m | 3.28° | 0.146 m | 4.682 m | 5.311 m |
| 2,745 m | 75.9 m | 3.77° | 0.170 m | not measured | not measured |

The wedge and shear both vary along the spiral, so they are computed for each module from the curve, never as one fixed value.

## Current implementation

`PathStitcher` (`res://tools/path_stitcher.gd`, formerly `PathMeshDeformer`) stitches modules along one path: it lays them end to end and bends them through the curve so they meet seamlessly. It builds the whole tower, 550 modules, in about 1.1 s in the editor. In `main.tscn` the nodes are `SpiralPath/TowerStitcher` and `HillRoadPath/HillRoadStitcher`, each a child of the path it follows. What it places comes from a `PathSequence` (see "Module sequences"); the old single hidden source block mode is gone, and the tower and the road are each a one-block sequence.

| Property | Type | Purpose |
| --- | --- | --- |
| `path_node` | NodePath (Path3D) | The curve to follow. Empty = use the parent, when it is a Path3D (the standard layout) |
| `sequence` | PathSequence | The building blocks (edited in the BUILDING BLOCKS section) |
| `bend` | FULL / LINEAR | How a block follows the path between its joints (see "Bend"). Shown as two buttons, Full | Linear |
| `start_offset` | float, 0.0 | Path distance of the first block's start joint |
| `up_mode` | WORLD / PATH | Vertical shear, or pitch and bank with the path |
| `flip_side` | bool | Mirror blocks across the path line (pz becomes −pz): the +Z side faces right instead of left. Offsets mirror with it. No visible change for a block that is symmetric about its centre line |
| `collision_prefix` | String, `Col-` | Collision only |
| `visible_collision_prefix` | String, `ColVis-` | Visible and collision |
| `generate_collision` | bool | Build StaticBody3D trimesh shapes |
| `chunk_size` | int, 10 | Modules per output mesh and collision body |
| Rebuild / Clear | Inspector buttons | Regenerate or remove the output |
| `summary` | read-only text | What the last build placed, and any warnings |

How it works:

1. Each block's scene is instanced once; its surfaces are collected into the module's local space and merged by material.
2. For each placed module, a lookup table of curve frames (P, L, U) is sampled every 0.05 m across the module's X extent.
3. Each vertex is mapped by interpolating that table; normals and tangents go through the Jacobian.
4. Every `chunk_size` modules are combined into one MeshInstance3D (one surface per material) and one StaticBody3D holding their collision (see "Draw-call efficiency").

**Placement.** The standard layout is the stitcher as a child of the Path3D it follows (with `PathMarker`s and `PathGroundDraper` as siblings under the same path). The path is then found automatically, and moving or rotating the path moves the blocks with it. The stitcher can also live elsewhere with `path_node` set; it rebuilds when the path's transform changes either way. Keep a parent path's scale at 1: a child inherits the scale and the blocks would be distorted (the node shows a configuration warning). The node also warns when it has no path, the path has no curve, or no building blocks are set.

The output sits under an unowned `_Generated` child. It is rebuilt on load and never saved into the scene, which keeps `main.tscn` small.

Status: deformation works across the whole spiral (550 modules) and the hill road (38 modules); `Col-` / `ColVis-` collision works, and generated trimesh shapes collide from both sides (`backface_collision`) so single-plane floors and walls are solid.

### Up mode

| Property | Values | Effect |
| --- | --- | --- |
| `up_mode` | `WORLD` (default) | Up is world up; slope becomes a vertical shear, walls stay vertical (the tower) |
| | `PATH` | Up is perpendicular to the path, from Curve3D up vectors including point tilt; modules pitch and bank (a road on a hill) |

Modules deform only at their vertices: a single-quad road piece cannot bend within itself, so subdivide modules that must follow curvature.

### Bend

| `bend` | Behaviour | Output |
| --- | --- | --- |
| `FULL` (default) | Every vertex is mapped through the curve (frames sampled every 0.05 m), so a block bends smoothly with the path. Best for organic and sculpted forms | Unique deformed meshes, merged by material and chunked (see "Draw-call efficiency") |
| `LINEAR` | Only the block's two end frames (position, left and up at the start and end joint) are used, and every vertex between them is blended in a straight line: wedge and shear, no bend. Seams still meet exactly, because neighbours share the joint frame. On a tight curve a straight block cuts across it like a chord (about 0.14 m at most on the tower). Best for architectural blocks | GPU instancing (below) |

Both modes use the same maths per vertex; Linear simply uses a two-entry frame table instead of one every 0.05 m. Changing any SHAPE, COLLISION or OUTPUT setting rebuilds the output automatically (about 0.3 s).

### GPU instancing (Bend: Linear)

In Linear mode every copy of a block is the same mesh and differs only in its two end frames, so one `MultiMeshInstance3D` per (block type, material) draws all copies and no CPU deformation or chunking is needed for rendering.

- **Per-instance data:** six Vector3 per placement (position, left, up at the start joint, then at the end joint), stored in a small `RGBAF` texture (6 texels wide, one row per instance) and read with `texelFetch(…, INSTANCE_ID)`.
- **Vertex shader:** blends the two frames by the vertex's X position and maps vertex, normal, tangent and binormal exactly as the CPU does (normals through the inverse transpose of the Jacobian). The shader is generated by the stitcher (`INSTANCE_SHADER`); one is created per cull mode and shared.
- **Materials:** plain opaque `StandardMaterial3D`s are converted automatically: albedo colour and texture, normal map, roughness and metallic values and textures (with their channels), specular, UV1 scale and offset, cull mode. Anything fancier (transparency, emission, triplanar, vertex colour, AO, rim, clearcoat, anisotropy, heightmap, subsurface, backlight, refraction, detail, proximity or distance fade, billboard, unshaded) stays on the CPU path so it still looks right. Godot offers no scripting access to a standard material's generated shader, so the instancing shader is hand-written.
- **Collision** is still built on the CPU (trimesh per chunk) from the `Col-` / `ColVis-` parts; only the visible parts are instanced. Bounds: each instance has an identity transform, so the stitcher sets `custom_aabb` on each MultiMeshInstance3D to the part of the path it covers.
- **Measured on the tower** (316 blocks, Block0 ×102, Block1 ×213, road1 ×1): rebuild 340 ms → 31 ms, drawn by 7 instanced meshes; collision unchanged (22 bodies, 8,958 triangles).

### Draw-call efficiency (standard behaviour)

Deformed modules cannot use plain GPU instancing: every module bends differently, so no two meshes are identical. The stitcher instead minimises draw calls in two standard steps:

1. **Merge by material, once, before deforming.** All source parts are baked into module space and concatenated into one set of arrays per (material, collision flags) combination. Block1's 22 parts become 3, which also cuts deformation work per module. Only attributes every part has are kept, so mixed source formats merge safely.
2. **Chunk after deforming.** `chunk_size` consecutive modules (default 10; 1 = one per module) are concatenated into one MeshInstance3D with one surface per material, and one StaticBody3D whose trimesh holds the chunk's collision. Chunks keep their own bounds, so off-screen chunks are still culled.

Draw calls scale with chunks × materials, not modules × parts. Measured on the tower (550 modules, 1.04 M vertices, unchanged):

| Build | Mesh objects | Surfaces | Collision bodies | Draw calls per frame (editor view, with shadows) |
| --- | --- | --- | --- | --- |
| One mesh per module, one surface per part | 550 | 12,100 | 550 | ~30,900 |
| Merged by material, chunk_size 10 | 55 | 165 | 55 | ~770 (whole scene) |

Source parts stay separate in Blender; merging happens on every rebuild.

**Future: instancing for Bend: Full.** The same instancing needs a per-vertex bend of the whole curve, not just the two end frames, so each block would read a denser table of frames from the data texture. Not built; Full keeps the CPU-merged chunks.

### Draping a path onto the ground

`PathGroundDraper` (`res://tools/path_ground_draper.gd`), a child of a Path3D, has a **Drape** button. It optionally re-spaces the points (`resample_spacing`), ray-casts each point straight down onto physics collision, sets its height to the hit plus `height_offset`, rebuilds smooth handles, and with `bank_to_ground` sets each point's tilt so the curve's up vector matches the ground normal. Generated modules are ignored, and the change is one undoable editor action. Use with `up_mode = PATH`.

On the Tower of Babel hill (a 20 m cone frustum whose top, at Y = 16, buries the tower's first turn), the draped road sits within 3 cm of the slope and banks 3.5° to 5.6°; at the ridge crease the single-quad road piece floats up to 0.3 m.

## Module sequences

A path is filled from **building blocks**: an optional first block, a block sequence, and an optional last block, plus markers. Example: `StartBlock`, then (4 × `Block1`, 2 × `Block2`) repeated, then `EndBlock`. The tower is the simplest case: a one-entry sequence, `Block1.blend`.

### Resources

Building blocks are Resources, stored inside the scene (or saved as a `.tres` and shared by several paths).

| Resource | Field | Purpose |
| --- | --- | --- |
| `PathModule` | `scene` (PackedScene) | The block, loaded from file. No placed source node is needed in the level |
| | `length` (float, 0 = auto) | Joint-to-joint length along the path (px); 0 uses the mesh's X extent minus `overlap` at each end |
| | `overlap` (float) | Built-in overlap at each end (Block1: 0.5 m, giving 5 m from a 6 m mesh) |
| | `stretch_to_length` (bool) | Along px, with a set `length`: off = Place (the block keeps its size and is placed every `length`; a longer length leaves gaps), on = Stretch (the block's mesh is stretched along the path to fill `length`, measured against its natural length: mesh extent minus overlap). Has no effect while `length` is 0 (auto) |
| | `offset_py`, `offset_pz` (float) | Per-block offset: py raises or lowers the block, pz shifts it sideways (+ = left of travel). Shown as Offset Vert and Offset Horz in the Inspector |
| `PathPatternEntry` | `module` (PathModule), `count` (int ≥ 1) | One row of the block sequence: `count` copies in a row, or the block's weight in random mode |
| `PathSequence` | `start` (PathModule, optional), `start_count` (int ≥ 1) | First block, placed `start_count` times at the path start |
| | `pattern` (Array of PathPatternEntry) | The block sequence, repeated to fill the path |
| | `mode` (PATTERN / RANDOM) | Repeat in order, or draw at random using each row's count as its weight |
| | `end` (PathModule, optional), `end_count` (int ≥ 1), `anchor_end` | Last block, placed `end_count` times at the path end |
| | `fit` (enum) | How the blocks meet the end exactly (below) |
| | `pattern_offset` (int) | Start the pattern part-way through, so neighbouring paths can continue each other's rhythm |
| | `random_seed`, `max_repeat` | RANDOM mode: the seed, and the longest run of one block |
| | `markers`, `marker_snap` | Blocks at specific distances (below) |

`PathStitcher.sequence` holds the `PathSequence`. When a PathStitcher is added as a child of a `Path3D`, its `path_node` is auto-assigned to `..` (an empty `path_node` also falls back to the parent path). A per-block `up_mode` / `flip_side` override is planned.

### Layout along the path

Modules no longer share one spacing. Each module i has its own length Lᵢ, and its start joint is the previous module's end joint:

```latex
s_0 = \text{start\_offset}, \qquad s_{i+1} = s_i + k\,L_i, \qquad c_i = s_i + \tfrac{1}{2} k\,L_i
```

A vertex x of module i maps to s = cᵢ + k·x, through exactly the same deformation as now. Adjacent modules still evaluate the same s at their shared joint, so seams stay exact even between different module types. k is the stretch factor from the fit mode.

### Fit modes (making the sequence end exactly at the path end)

| Mode | Behaviour |
| --- | --- |
| `STRETCH` (default) | Whole modules only; every module is scaled along the path by the same k so start + middle + end fill the length exactly |
| `TRUNCATE_PATTERN` | Pattern stops at the last whole module that fits before the end module; k is close to 1 but the pattern may end mid-cycle |
| `FINISH_CYCLE` | Only whole pattern cycles; k absorbs the difference (larger stretch, keeps the rhythm intact) |
| `NONE` | No stretch; the end module is placed at the path end and any gap or overlap before it is left visible |

Paths shorter than start + end use only the start module (stretched), with a warning.

### Build and efficiency

- Each distinct `PathModule` is collected and merged by material once, as now.
- Chunking is unchanged: `chunk_size` consecutive modules, of any types, become one mesh with one surface per material and one collision body. Draw calls still scale with chunks × materials.
- Closed paths: no start or end module; the pattern wraps, and the fit stretch makes the last joint meet the first.

### Anchored end

`PathSequence.anchor_end` (bool). When on, the last block is placed with its end joint exactly at the path end, unstretched, and the fit mode applies only to the stretch between the first block and the last block. Use it where a path must finish precisely, for example on a doorway or a junction.

### Random sequences

`PathSequence.mode`: `PATTERN` (fixed, as above) or `RANDOM`. In RANDOM mode the same block-sequence rows are used, and each row's number is its **weight** instead of a repeat count: `[{Block1, 4}, {Block2, 1}]` picks Block1 four times as often as Block2 (measured 79.7% against 80% over 40 seeds).

| Field | Purpose |
| --- | --- |
| `random_seed` (int) | Same seed gives the same layout on every rebuild and every machine |
| `max_repeat` (int, 0 = unlimited) | Longest allowed run of the same block |

Choices are drawn in path order from the seed, so a layout is stable until the seed or the rows change. First and last blocks, anchoring, fit modes and markers work the same in both modes.

### Markers

Markers place a specific module at a specific path distance, interrupting the sequence. Example: a Gate at s = 300 m.

| Field | Purpose |
| --- | --- |
| `markers` (Array of `{module, distance}`) on `PathSequence` | Module whose centre should land at that path distance |
| `marker_snap` (enum) | `EXACT`: the marker sits exactly at the distance, and the sequence segments either side are each fitted with the fit mode; `NEAREST_JOINT`: the marker replaces whichever sequence module is closest, no extra stretch |

The path is split at markers into segments: start → marker 1 → … → end. Each segment is filled with the pattern (or random draw) independently, and the pattern continues counting across segments, so the rhythm resumes after a marker. Markers can also be authored visually as child `Marker3D`s of the Path3D (snapped to the closest path distance), as an alternative to typing distances.

### Inspector workflow (everything via the GUI)

All setup happens in the **BUILDING BLOCK SEQUENCE** box at the top of a PathStitcher's Inspector, drawn by the **PathStitcher Inspector** editor plugin (`res://addons/path_stitcher/`). Godot's standard Inspector can only show lists of resources as nested sub-inspectors, so the plugin draws compact one-line rows instead. Each section sits in the editor's standard sub-inspector box.

The SHAPE group sits directly under Path Node, with **Bend** as two toggle buttons on one line (Full | Linear; each button has a tooltip, Linear's reads "Full instancing - GPU optimized"), then Start Offset, Up Mode and Flip Side. The building-block box follows, then Rebuild / Clear, the summary, COLLISION and OUTPUT.

```
+- BUILDING BLOCK SEQUENCE ------------------ [ ] Randomize -+
|  First  [ StartBlock.blend ..... v ]  ×[ 2 ]  >           |
|   ≡     [ Block1.blend ......... v ]  ×[ 4 ]  >   (trash) |
|   ≡     [ Block2.blend ......... v ]  ×[ 2 ]  v   (trash) |
|           Length (px) [ 0.00 m ]  Overlap [ 0.50 m ]       |
|           Offset Vert [ 0.00 m ]  Offset Horz [ 0.00 m ]   |
|           Along px    [ Place v ]  (Place | Stretch)      |
|           Auto length 5.00 m (mesh extent minus overlap)   |
|         [ <empty> .............. v ]  ×[ 1 ] (faded)       |
|  Last   [ EndBlock.blend ....... v ]  ×[ 3 ]  >           |
|         [ ] Anchor Last block to end of path               |
|  Fit    [ Stretch v ]     (Randomize on: Seed, Max repeat) |
+------------------------------------------------------------+
+- MARKERS -------------------------------------------------+
|  [ Gate.blend ] at [ 300.0 m ]  (trash)                    |
|  [ + Add marker ] [ Add marker here ]    Snap [ Exact v ]  |
+------------------------------------------------------------+
```

- **One column layout:** First, Last and every block row share the same columns (label or grip, scene box, multiplier, expander, remove), so the scene boxes line up.
- **Rows:** a grip (≡) to drag-reorder (drop it on another row's grip), a compact scene picker (shows the file name; Quick Load, Load, Clear, Show in FileSystem, or drag a `.blend` / `.glb` / `.gltf` / `.tscn` from the FileSystem dock onto it), the multiplier (`×N` copies; a weight when Randomize is on), an expander (>) for that block's length, overlap, Offset Vert and Offset Horz, an **Along px** dropdown (Place or Stretch, see `stretch_to_length`), and a remove button. The picker is a custom control because Godot's resource picker shows a large thumbnail for scenes.
- **First / Last multipliers:** `PathSequence.start_count` and `end_count` (min 1) repeat the first or last block, for example three end caps. With Anchor on, the repeated last blocks are all placed unstretched against the path end.
- **Empty slot instead of an Add button:** the list always ends with an empty picker. Choosing a scene in it, or dropping scene files on it (several files add one row each, one undo step), turns it into a block row and a new empty slot appears below. Dropping on a filled row's picker replaces that row's scene. Dragging nodes from the Scene dock is not supported.
- **First / Last block:** the same picker and expander; **Anchor Last block to end of path** (its own line under the Last row) pins the last block to the path end.
- **Randomize:** one toggle switches the sequence to a weighted draw and reveals Seed and Max repeat.
- **Markers:** rows of block and distance, plus **Add marker here**, which drops a `PathMarker` node on the path at the point closest to the editor camera (it snaps to the path as it is dragged; its block is set in its own Inspector).
- **Undo:** every edit is one undoable editor action, with merging for repeated edits to the same field.
- **Live rebuild:** any change rebuilds the output automatically (debounced, about 0.3 s). **Rebuild** and **Clear** stay for manual use, and a read-only **summary** shows what was placed, for example "43 modules (Road x15, Block1 x28), stretch 0.994", plus warnings (path too short, stretch over 10%, marker overlapping the first or last block).
- **If the plugin is off:** the sequence shows as Godot's standard resource slot and everything still works, just less conveniently.

## Movement axes system (optional)

The path supplies the player's movement axes: forward runs along the curve and right is perpendicular to it. The player's controller decides what to do with them. Nothing constrains the player to the path. The feature is off by default and enabled for the Tower of Babel test.

At the player's position p:

1. Find the closest path distance: s = `curve.get_closest_offset(p)`, in the path's local space.
2. **Forward** F = the curve tangent at s, pointing towards increasing s. **Back** = −F.
3. **Right** R = F × Û, normalised. **Left** = −R. Right stays horizontal, so strafing never climbs.
4. The controller builds its move vector: `move = F * input.y + R * input.x`.

Forward is offered in two forms, chosen by the controller:

| Vector | Definition | Use |
| --- | --- | --- |
| `forward` | 3D tangent, includes the slope | Ramps, flying, skating on a grade |
| `forward_flat` | Tangent with Y removed, normalised | Walking characters that let physics handle height |
| `right` | F × Û, always horizontal | Strafing |
| `up` | World up | Jumping |

The provider also reports useful by-products of the same query: the path distance s, the signed lateral offset from the centre line, and the distance to the path.

**Direction of travel.** The provider's forward always points along increasing s. Travelling the other way is the controller's choice: the test player keeps a `travel_dir` (+1 / −1) and flips it when turned more than 90° from forward, so the path's backward direction becomes its forward (see "Test player and tuning").

## Branching paths

Whichever path the player is closest to supplies the movement axes. At a fork the player can steer towards either branch; as they move closer to one, that branch takes over. No branch is ever chosen for them.

**Authoring.** A branch is simply another Path3D that starts at, or near, a point on an existing path. Paths join a group (`movement_paths`) or register with a shared `PathAxesField` node. No explicit graph of junctions is needed for v1.

**Selection.** Each physics frame the player's `PathAxesFollower` queries every registered path and picks the one with the smallest distance to the player. To keep this cheap, paths outside a search radius (their AABB grown by `max_distance`) are skipped.

**Switching without jitter.** Where two branches are almost equally close, a plain nearest-path rule would flip back and forth. Two measures prevent that:

- **Hysteresis:** the current path stays active until another path is closer by more than `switch_margin` (for example 0.5 m).
- **Blending:** over a `blend_distance` either side of the switch point, the axes are blended between the two paths, weighted by distance, then re-normalised. Forward never snaps through a large angle in one frame.

**Opposed branches.** If two paths meet head-on (their forwards more than 90° apart), the blend would cancel out. Before blending, a path's axes are flipped when its forward points away from the current forward. This keeps "forward" meaning "the way I was going".

**No path in range.** Beyond `max_distance` from every path, the follower returns its last axes (or world axes, as a setting) and reports `has_path = false`.

```
                         blend zone
                        ┌──────────┐            Branch A (active)
                        │      ____│_______________________
                        │ ____/    │   player o──► forward
  Trunk path ___________│/         │          │
                    fork●\____     │          ▼ right
                        │     \____│_______________________
                        │          │            Branch B
                        └──────────┘
```

The player has steered towards Branch A and is now closer to it by more than the switch margin, so A supplies forward and right. Inside the blend zone the axes are blended between the two branches.

## API sketch: movement provider

Two small nodes, kept separate from the stitcher so either can be used alone. The stitcher gains one flag that registers its path as a movement path.

| Node / member | Kind | Purpose |
| --- | --- | --- |
| `PathStitcher.provide_movement_axes` | bool, default false | Adds the stitcher's path to `movement_paths` |
| `PathAxesField` | Node | Holds the registered paths and answers queries |
| `PathAxesField.query(p: Vector3) -> PathAxes` | method | Nearest path and its axes at world point p |
| `PathAxesFollower` | Node, child of the player | Runs the query each physics frame, applies hysteresis and blending |
| `switch_margin` | float, 0.5 m | Hysteresis before changing path |
| `blend_distance` | float, 2 m | Width of the blend zone between paths |
| `max_distance` | float, 20 m | Beyond this, no path is active |
| `use_flat_forward` | bool | Return `forward_flat` as `forward` |
| `path_changed(path)` | signal | Fired when the active path changes |

`PathAxes` result (a small RefCounted or Dictionary): `forward`, `forward_flat`, `right`, `up`, `path`, `path_coords` (Vector3 px, py, pz), `distance`, `has_path`.

Use in a CharacterBody3D:

```gdscript
var input := Input.get_vector("left", "right", "back", "forward")
var a: PathAxes = $PathAxesFollower.axes
velocity = (a.forward * input.y + a.right * input.x) * speed
move_and_slide()
```

## Test player and tuning

The Tower of Babel test uses a skateboarding player that consumes the movement axes. It is game code, not part of the reusable system, but it exercises every axis feature.

**Tuning.** All play values live in one `GameParams` resource (`res://game_params.gd`, instance `res://game_params.tres`) assigned to the scene root (`main.gd`); scripts read `GameParams.get_active()`. Groups: PLAYER SCALE, SKATING, SKATER VISUAL, CAMERA, PATH AXES. Edits reach a running game live. `PathAxesFollower.use_game_params` (default on) takes its switch/blend/max distances from there.

| Input | Effect |
| --- | --- |
| W | Kick (skate/kick animation blend); holding chains kicks, crossfading between two kick layers; impulse lands at `kick_impulse_point` of the animation |
| S | Brake impulse (never below zero) and a lean back towards the camera |
| A / D | Strafe, lean, and turn (yaw) at `turn_speed` up to `turn_max`; snaps back on release |
| Turn past `reverse_angle` / `forward_return_angle` (both 90°) | Travel direction flips: the path's backward direction becomes forward (backtracking), and back again |
| Arrow keys | Orbit the camera; left/right also steer the movement forward (`steer_with_camera`), easing back on release |
| − / + | Zoom; held for `camera_zoom_hold` then eases back |
| Space | Jump |

- **Speed model:** each kick adds `kick_impulse` up to `max_speed`; speed fades linearly to zero over `rollout` seconds from the last impulse; walls remove speed.
- **Airborne:** horizontal velocity is frozen at take-off; no kicking, turning or braking; a kick in progress fades to skate over `kick_air_cancel_time`.
- **Camera follow:** dead zone up to `camera_follow_start` (20°) between camera and skater heading, then a linear ramp to the skater's `turn_speed` at `camera_follow_lock` (30°), which is a hard limit; re-centres on the travel forward with a smooth damp over `camera_recenter_time`. The camera follows the A/D heading but not camera steering (which comes from the camera itself).
- **Board trail:** a `GPUTrail3D` node (the GPUTrail addon by celyk, MIT, `res://addons/GPUTrail/`) named `BoardTrail` under the skater, at the tail end of the board.
- **Player scale:** `player_scale` multiplies the model, collider, camera distances, speeds and jump; with `scale_gravity` gravity scales too, so a small player moves like a normal-sized person and the world reads as giant.

## Acceptance tests

| Test | Pass when |
| --- | --- |
| Straight path | Modules match the source exactly, no deformation |
| Constant arc | No gaps; outer face longer and inner face shorter by z × Δθ |
| Straight ramp | Adjacent floors and arches meet with no vertical lip |
| Tower of Babel spiral | Wedge and shear combine cleanly over all 550 modules |
| Changing curvature | Seams stay closed as the radius goes from 100 m to 75 m |
| Collision | `ColVis-` floors are visible and walkable; `Col-` meshes collide but do not render |
| Axes on a straight path | Forward equals the path direction; right is horizontal and perpendicular |
| Axes on the spiral | Holding forward walks the player up the ramp without steering |
| Free movement | The player can step off the path line in any direction; nothing pulls them back |
| Branch at a fork | The active path changes only after crossing the switch margin; no flicker |
| Blend at a fork | Forward turns smoothly through the blend zone, with no frame-to-frame jump over 5° |
| Opposed branches | Forward does not reverse or cancel where two paths meet head-on |
| Out of range | Beyond `max_distance`, `has_path` is false and the last axes are kept |

## Roadmap

- [x] Deform and repeat a module along a Curve3D, with wedge and shear (GDScript)
- [x] Centred-Z modules, 5 m spacing with overlap, trimesh collision
- [x] `Col-` / `ColVis-` naming, double-sided trimesh collision
- [ ] Close visual check of the seams on the spiral
- [x] Movement axes: `PathAxesFollower` (nearest path in the `movement_paths` group, hysteresis, blending), skater player on the hill road and spiral
- [ ] `PathAxesField` (shared query node) — the follower currently queries the group directly
- [ ] Branching: a test fork to verify hysteresis, blending and opposed-branch handling in play (implemented, untested)
- [x] Ends-only deformation: Bend: Linear
- [x] Merge parts by material and chunk modules (draw calls ~30,900 → ~770)
- [x] `up_mode` PATH, `PathGroundDraper`
- [x] Skater player and tuning (see "Test player and tuning")
- [x] Module sequences: `PathModule` / `PathSequence` resources, first / sequence / last blocks, fit modes, anchored end, weighted random sequences, markers, `PathMarker`, live rebuild, summary readout
- [x] BUILDING BLOCKS Inspector (editor plugin): reorderable rows, counts, per-block length / overlap / py / pz offsets, undo
- [ ] Per-module `up_mode` / `flip_side` overrides on `PathModule`
- [ ] Closed-loop paths (pattern wraps, no start/end)
- [x] Bend option (Full | Linear) and GPU instancing for Linear
- [ ] Instancing for Bend: Full (dense frame table in the data texture)
- [ ] Instancing for more material types (transparency, emission, triplanar)
- [ ] Bake modules and collision to files
- [ ] Port to a GDExtension, then compare with Godot proposal #12844

## Open questions

- Should forward follow the slope by default (`forward`) or stay level (`forward_flat`)? The test player uses `forward_flat` and lets physics handle height.
- Should the movement axes come from a separate centre-line path, so the walking line can differ from the line the meshes follow?
- Is nearest-path enough, or do some forks need a hint, such as a priority value per path?
- Resolved: the camera is game code. The test camera follows the player's heading with a dead zone, a ramp and a hard limit.
