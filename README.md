# PathStitcher

Distribute modular "building blocks" along a path with seamless beauty. Envelope distortion ensures the leading and trailing edge of each block meet perfectly. Blocks are wedged and sheared to give a true organic feel.

Use it for street and tower architecture, roads, walls, fences, bridges, tracks, railings, etc.

![A spiral tower built by PathStitcher from two repeating blocks](docs/images/tower_demo.png)

## Why PathStitcher

- **Wedge.** On a turn, a block's outer face lengthens and its inner face shortens, so neighbours still meet edge to edge. No fans of gaps on the outside of a bend, no overlaps on the inside.
- **Shear.** On a slope, each block's ends take the path height at their own joint, and walls stay vertical. Or switch to Path up-mode and blocks pitch and bank with the path (a road on a hill).
- **Exact joints.** Neighbouring blocks evaluate the same curve point at their shared joint, so seams coincide by construction, not by tolerance.
- **Fine-grained control in the Inspector.** A BUILDING BLOCKS section on the node lets you set:
  - sections: several stretches along one path, laid end to end, each with its own length and its own pattern
  - in each section, a different first block and last block, each with a count
  - a reorderable pattern of blocks with per-block counts, repeated continuously, repeated a set number of times, or picked at random
  - per-block length, overlap, stretch, and offsets along, above and beside the path
  - how the blocks fit the path length (stretch, truncate, finish the cycle, or none)
  - markers: special blocks at fixed path distances
- **Fast.** In Linear mode every copy of a block shares one mesh, and only a small "envelope" differs per copy (see [Efficiency](#efficiency)).
- **Collision from your meshes.** Name mesh objects `Col-` (collision only) or `ColVis-` (visible and collision) and PathStitcher builds trimesh collision for them.
- **Ground draping.** `PathGroundDraper` drops a path onto the ground below it and banks the curve to match.
- **Optional movement axes.** `PathAxesFollower` gives a character forward and right vectors taken from the nearest path.

PathStitcher is a normal node: add it as a child of a `Path3D`. You don't place blocks as child nodes. Pick them in the Inspector, and the generated result appears under an unsaved `_Generated` child.

Tested with **Godot 4.7**.

## Efficiency

In Linear mode, deforming a block needs only its **envelope**: the position, side and up vectors at its start joint and at its end joint (six `Vector3`). The vertex shader blends between those two frames by each vertex's position along the block, and maps vertices, normals and tangents the same way the CPU path does. This has three consequences:

- **One mesh per block type.** Every copy of a block is the same mesh. One `MultiMeshInstance3D` per block type and material draws all of them, however many copies the path needs.
- **No CPU deformation.** Each copy's envelope is one row in a small float texture, read in the shader with `texelFetch`. The stitcher never rewrites vertex data, so rebuilding after a curve edit only recomputes the envelopes.
- **Exact seams.** Neighbours share a joint frame, so adjacent copies still meet exactly.

Measured on a 316-block tower, a rebuild takes about 31 ms instead of 340 ms with CPU deformation, and the visible blocks are drawn as 7 instanced meshes. Collision is still built on the CPU as trimesh per chunk.

The trade-off is that an envelope blends in a straight line between its two joints, so a long block on a tight curve cuts across it like a chord (about 0.14 m at most on the tower). Use **Full** bend for blocks that must follow the curve along their length. It deforms every vertex on the CPU and merges the results into chunked meshes, which suits organic shapes.

## Install

1. Copy `addons/path_stitcher` into your project's `addons/` folder (or install from the Asset Library).
2. Open **Project > Project Settings > Plugins** and enable **PathStitcher**.

## Quick start

1. Add a `Path3D` and draw a curve.
2. Add a `PathStitcher` as a **child** of the path. It follows its parent by default.
3. In the Inspector, open **BUILDING BLOCKS** and pick a block scene (a `.blend`, `.glb` or `.tscn`) for the first section.
4. The blocks appear along the path and rebuild whenever you edit the curve or any setting.

Output is generated under an unowned `_Generated` child. It is rebuilt on load and never saved into your scene.

## Demo

This repository is a small Godot project. Open `demo/project.godot` in Godot, open `tower.tscn` and run it (F6) to see a Tower of Babel built by one `PathStitcher` on one spiral `Path3D`. The spiral makes three and a half turns, tightening from 32 m to 14 m radius while rising 16 m per turn, so every block is wedged and sheared differently.

The building blocks (in `demo/blocks/`) are each 5 m joint to joint, with no overlap:

- **First block:** `base_block`, a solid 16 m block, placed 12 times to form the base (and once more as the last block).
- **Block sequence:** `tower_block`, repeated. Its lower storey is an open arcade (pillars with arches running both along and across the path), and its upper storey is a solid wall with a round-headed window. Each turn of the spiral stands on top of the one below.

The spiral is a `PathSpiral` node. To reshape it, select it and change **Turns**, **Start Radius**, **End Radius** and **Rise Per Turn** in the Inspector (**Direction** chooses clockwise or anticlockwise winding); the tower follows live. Set Rise Per Turn to the block height (16 m) so each turn rests on the one below. Turn on **Snap Values** to round the radii and rise to a step you choose (default 0.5 m) and the turns to quarter turns; leave it off for free values down to 0.01.

The demo is not included in the addon zip.

## Many towers

For a game with many towers, save one tower as its own scene (a `PathSpiral` with a `PathStitcher` child) and instance it wherever you need one. Turn on Editable Children on an instance to give that tower its own turns and radii. Save the sections as shared `.tres` `PathSection` files so every tower uses the same ones. In Linear mode each tower draws with a few instanced meshes, so many towers stay cheap.

## Authoring blocks

A block is any scene, authored in its own local space:

| Axis | Convention |
| --- | --- |
| +X | Along the path. The length of the block. |
| +Y | Up. Floor at Y = 0. |
| +Z | Sideways, to the right of travel. The path runs through the centre of Z. |

A block is only rotated onto the path, never mirrored, so it looks exactly as you authored it. Origin at the centre of X and Z, at floor level. Give each block a small `overlap` (for example 0.5 m at each end) so the joint hides under its neighbour. Blocks only deform at their vertices, so subdivide any piece that must bend within itself, such as a flat road quad.

**Collision naming** (prefixes are editable on the node):

| Object name starts with | Rendered | Collision |
| --- | --- | --- |
| `ColVis-` | yes | yes (trimesh) |
| `Col-` | no | yes (trimesh) |
| anything else | yes | no |

## Nodes and resources

| Class | Purpose |
| --- | --- |
| `PathStitcher` (Node3D) | Builds the blocks along a `Path3D`. |
| `PathSection` (Resource) | One stretch of the path: a length, a start block, a repeating pattern, an end block and fitting. A stitcher lays its sections end to end. |
| `PathModule` (Resource) | One block: its scene, length, overlap, stretch and offsets. |
| `PathSpiral` (Path3D) | Optional. A path that builds its own spiral curve from Inspector settings: turns, start and end radius, rise per turn. Any `Path3D` works with a `PathStitcher`; this one just saves you placing points by hand. |
| `PathCircle` (Path3D) | Optional. A path that builds a flat circle from one setting, `radius`. Move, rotate or scale the node to place it. |
| `PathMarker` (Marker3D) | Place a block at a spot on the path by moving this node. |
| `PathGroundDraper` (Node3D) | Child of a `Path3D`. The **Drape** button lays the curve onto physics collision below it. |
| `PathAxesFollower` (Node) | Child of a `Node3D`. Supplies forward and right axes from the nearest path in a group. It never moves its parent. |

### PathStitcher properties

| Property | Meaning |
| --- | --- |
| `path_node` | The curve to follow. Defaults to the parent. |
| `sections` | The `PathSection`s, laid end to end from the start of the path. |
| `markers`, `marker_snap` | Blocks at fixed path distances, across all sections. |
| `bend` | **Linear** (default): each block is blended between its two end frames, so it is wedged and sheared but does not bend. Seams still meet exactly. Drawn with GPU instancing. **Full**: every vertex follows the curve smoothly. Best for organic shapes, built on the CPU. |
| `up_mode` | **World**: walls stay vertical and slope becomes a shear (towers). **Path**: blocks pitch and bank with the path (roads on hills). |
| `start_offset`, `end_offset` | Move where the blocks start and stop along the path. |
| `flip_side` | Mirror the blocks across the path, so +Z faces the left of travel instead of the right. |
| `generate_collision` | Build trimesh collision from `Col-` and `ColVis-` meshes. |
| `chunk_size` | Modules combined per mesh and collision body (Full mode). |
| Rebuild, Clear | Inspector buttons. |

### PathSection

| Property | Meaning |
| --- | --- |
| `title` | An optional name shown in the Inspector. |
| `length` | How far along the path the section runs. 0 shares whatever the other sections leave over, so give the last section 0 to fill the rest. |
| `start`, `end` (+ counts) | Optional first and last block. |
| `mode` | **Pattern** repeats the rows in order. **Random** draws from them, using each row's count as its weight. |
| `pattern` | Rows of block and count, for example 4 of `Block1`, then 2 of `Block2`. |
| `repeat_count` | 0 repeats the pattern continuously to fill the section. A number places the pattern that many times, unstretched. |
| `fit` | How blocks fill the path: **Stretch** (all blocks scaled slightly), **Truncate pattern** (whole blocks, then stretch to close the gap), **Finish cycle** (whole pattern cycles only), **None** (no stretch; a gap may show). |

### PathModule

| Property | Meaning |
| --- | --- |
| `scene` | The block scene. |
| `length` | Joint-to-joint length along the path. 0 means auto: the mesh's X extent minus the overlaps. |
| `stretch_to_length` | With a set `length`: stretch the block to fill it instead of leaving gaps. |
| `overlap` | Overlap built into each end of the mesh. |
| `offset_px`, `offset_py`, `offset_pz` | Shift along, above and beside the path. |

## Path coordinates

Offsets use path coordinates: `px` is distance along the path (forward is the direction of the curve's points), `py` is height along world up, and `pz` is sideways, positive to the right of travel (the side +Z faces).

## Notes and limits

- Linear-mode instancing converts plain opaque `StandardMaterial3D`s automatically. Transparency, emission, triplanar and the more exotic material features are not supported there; use Full mode for those.
- Hiding a stitcher or its path turns its collision off.
- A stitcher rebuilds when its path's transform changes, so you can move the path freely.

## Contributing

The addon is everything under `addons/path_stitcher/`. The Godot demo project is in `demo/`, where `demo/addons/path_stitcher` is a symlink to the addon. See `docs/PathStitcher_Spec.md` for the full design notes.

## Licence

MIT. See [LICENSE](LICENSE). Sample meshes and textures in the test project may carry their own licences; they are not included in the addon.
