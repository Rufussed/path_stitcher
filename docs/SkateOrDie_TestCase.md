# SkateOrDie: the PathStitcher test case

Rufus Lane · A Godot scene used to exercise PathStitcher: a spiral tower, a bridge, a second tower, and a skateboarding player. The tool itself is specified in `PathStitcher_Spec.md`; this document is only about the scene.

## Purpose and scope

SkateOrDie is not a game; it is a test bed. It exercises every PathStitcher feature on real geometry: a tight, tapering spiral (wedge and shear together), a level run (the bridge), and the same spiral reversed (a mirrored copy using Flip Side). The skateboard player consumes the movement axes and so exercises the optional movement system, free roaming and path switching.

## The scene

- **Files:** `main.tscn` (the scene, `main.gd` registers the `GameParams`), `player/` (the player scene and scripts, the camera, the HUD), `game_params.gd` and `game_params.tres` (all tuning), `blendot_meshes/` and `assets/` (the Blender blocks and the skater), `addons/GPUTrail` and `addons/sky_3d` (third-party).
- **Tower (`SpiralPath` / `TowerStitcher`):** 50 m radius at the base, shrinking 5 m per revolution and stopping at 11 m after 7.8 revolutions, 124.8 m up. Blocks: `Block0` (solid base) ×51, `Block1` (arches) repeated, a last `Block0`. Bend: Linear (GPU instanced).
- **Bridge (`BridgePath` / `BridgeStitcher`):** starts exactly at the top of the tower and runs roughly level to the start of the second tower (200 m as first built; since bent by hand). Blocks: `road1`.
- **Second tower (`Tower2Path` / `Tower2Stitcher`):** the tower path reversed (top to bottom), turned 180° so it continues in the bridge's heading, with its start at the bridge end. Same blocks with First and Last swapped and **Flip Side on**, so the arcades stay on the outside. Together the three paths form one continuous route.
- **Ground and sky:** a green cone-frustum ground and the Sky3D addon. The ground was built for the original tower and the hill road (since removed), so it no longer matches the towers.
- **Block textures:** the four Blender blocks (`Block0`, `Block1`, `road1`, `Road`) share six 512 × 512 WebP textures (basecolor lossy, normal and roughness lossless) in `blendot_meshes/textures/`, referenced by relative path from each `.blend` the same way the skater's textures are, instead of 4096 px copies packed into every file. Each `.blend` is about 100 KB (was about 9 MB).
- **Block conventions:** X along the path, Y up, Z sideways, origin at the centre; `Col-` and `ColVis-` prefixes for collision; `Block1` has 0.5 m built-in overlap at each end.

## Test player and tuning

The Tower of Babel test uses a skateboarding player that consumes the movement axes. It is game code, not part of the reusable system, but it exercises every axis feature. The player is its own scene, `player/player.tscn` (root facing −Z, rotation 0).

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
| Left Shift | Toggle path following / free roaming (arrow at the bottom centre of the screen) |

- **Speed model:** each kick adds `kick_impulse` up to `max_speed`; speed fades linearly to zero over `rollout` seconds from the last impulse; a wall keeps the part of the speed along it (below), and a near head-on hit takes the speed away so it cannot build up against the wall.
- **Airborne:** horizontal velocity is frozen at take-off; no kicking, turning or braking; a kick in progress fades to skate over `kick_air_cancel_time`.
- **Camera follow:** dead zone up to `camera_follow_start` (20°) between camera and skater heading, then a linear ramp to the skater's `turn_speed` at `camera_follow_lock` (30°), which is a hard limit; re-centres on the travel forward with a smooth damp over `camera_recenter_time`. The camera follows the A/D heading but not camera steering (which comes from the camera itself).
- **Lips and walls (COLLISIONS in `GameParams`):** `step_height` (1 m, in world metres, not scaled by `player_scale`): a low obstacle that blocks only the lowest part of him is ignored; the body moves up to the new ground height at once with no loss of speed, and the view and camera ease up at `step_smooth_speed`. Walkable slopes are not treated as lips. On hitting a wall he keeps the component of his speed that runs along it and slides along it without friction; a near head-on hit takes the speed away. A first hit pushing into the wall at least `wall_rebound_min_speed` also pushes him back off along the surface normal by `wall_rebound_distance` (1 m at player_scale 1, so scaled with the player; 0 = off), once per 0.5 s. Rebound is ground only.
- **Turn twist:** while A/D is held (on the ground) the skater model also twists `turn_twist_angle` (10°) further into the turn, easing in and out over `turn_twist_time` (0.5 s); visual only.
- **Kick animation speed:** the kick plays through TimeScale nodes in the AnimationTree, and its speed follows the player's speed every frame: `kick_anim_speed_still` (1) at a standstill rising linearly to `kick_anim_speed_fast` (2) at `kick_anim_fast_at` (m/s at player_scale 1), times `kick_speed`. The impulse timing is tracked in animation seconds, so it still lands at `kick_impulse_point` whatever the speed does mid-kick. The TimeScale values shown in the tree editor are overwritten at run time.
- **Braking:** S leans the skater back about `brake_pivot` (the centre of the back wheels, so they stay planted while the nose lifts) by `brake_lean_angle`; a kick in progress fades out over `kick_brake_cancel_time`. Sparks from the dragging tail start once the lean reaches `spark_lean_threshold` of the full angle, and not below `spark_min_speed`.
- **Board trails:** `GPUTrail3D` nodes (the GPUTrail addon by celyk, MIT, `res://addons/GPUTrail/`; Trail1 to Trail4) under the skater, sharing one colour ramp (60% alpha at the start, fading to nothing). A trail's width runs along the node's local Y axis, so for a flat ribbon Y must point across the board.
- **Player scale:** `player_scale` multiplies the model, collider, camera distances, speeds and jump; with `scale_gravity` gravity scales too, so a small player moves like a normal-sized person and the world reads as giant.

## Acceptance tests

| Test | Pass when |
| --- | --- |
| Tower of Babel spiral | Wedge and shear combine cleanly over all 550 modules |
| Changing curvature | Seams stay closed as the radius goes from 50 m to 11 m |
| Axes on the spiral | Holding forward walks the player up the ramp without steering |
| Free movement | The player can step off the path line in any direction; nothing pulls them back |

## Roadmap

- [x] Skater player and tuning (see "Test player and tuning" above)
- [x] Free roaming and Left Shift path following, with the HUD arrow; ambiguity distance; hidden paths ignored
- [x] Step over small lips, frictionless wall sliding and rebound
- [x] Level bridge from the tower top to a second, reversed tower

## Open questions

- Resolved: the camera is game code. The test camera follows the player's heading with a dead zone, a ramp and a hard limit.
