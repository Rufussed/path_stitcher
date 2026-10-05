class_name GameParams
extends Resource
## Every play-tuning value in one place. The scene root (main.gd) holds the
## active instance (res://game_params.tres); scripts read GameParams.get_active().
## Edits to the .tres in the Inspector reach a running game live.

static var _active: GameParams
static var _fallback: GameParams


## The scene's params, or defaults when no scene has registered any.
static func get_active() -> GameParams:
	if _active:
		return _active
	if _fallback == null:
		_fallback = GameParams.new()
	return _fallback


static func set_active(params: GameParams) -> void:
	_active = params




# ==============================================================================
#
#   PLAYER SCALE
#
# ==============================================================================

@export_group("PLAYER SCALE")

## Size of the player relative to the authored model. Scales the model,
## collider, camera distances, speeds and jump, so 0.1 makes the world look
## 10x larger. Angles and timings are unchanged.
@export_range(0.01, 10.0, 0.01, "or_greater") var player_scale := 1.0

## Scale gravity with the player too, so a small player moves and falls like a
## normal-sized person (the world looks giant). Off = real gravity (a toy).
@export var scale_gravity := true




# ==============================================================================
#
#   SKATING  -  kick, brake, rollout, speed, strafe, turn, jump
#
# ==============================================================================

@export_group("SKATING")

## Speed added by each kick (m/s at player_scale 1).
@export var kick_impulse := 20.0

## When in the kick animation the impulse lands (0 = start, 0.5 = halfway, 1 = end).
@export_range(0.0, 1.0) var kick_impulse_point := 0.5

## Crossfade time between skate and kick, and between chained kicks (s).
@export var kick_blend_time := 0.5

## When the skater leaves the ground mid-kick, the kick fades out to the skate
## animation over this time (s), so it never plays out in the air.
@export var kick_air_cancel_time := 0.1

## Speed removed by each brake press (m/s).
@export var brake_impulse := 3.0

## Seconds for speed to fade from its value at the last kick impulse to zero.
@export var rollout := 10.0

## Speed cap (m/s).
@export var max_speed := 300.0

## Sideways speed from A/D (m/s).
@export var strafe_speed := 6.0

# --- Turn (A / D) ---

## While A/D is held the skater also turns (yaws) left/right at this rate (degrees per second).
@export var turn_speed := 110.0

## Furthest the A/D turn can take the skater from the current forward (degrees).
## Must exceed reverse_angle for A/D alone to turn you round.
@export var turn_max := 120.0

## How quickly the turn snaps back to the forward direction when A/D is released.
@export var turn_return_speed := 12.0

## Turning (A/D plus camera steering) further than this from forward makes the
## path's backward direction the new forward, so you can backtrack (degrees).
@export var reverse_angle := 90.0

## While travelling backwards, turning further than this makes the path's
## official forward the forward again (degrees).
@export var forward_return_angle := 90.0

# --- Jump ---

## Upward speed of a jump (m/s).
@export var jump_speed := 10




# ==============================================================================
#
#   SKATER VISUAL  -  facing, side lean, brake lean
#
# ==============================================================================

@export_group("SKATER VISUAL")

## How quickly the skater turns to the path direction.
@export var turn_rate := 6.0

## Extra yaw for the skater model if it faces the wrong way (degrees).
@export var model_yaw_offset := 0.0

# --- Side lean (A / D) ---

## How far the skater leans into A/D strafing (degrees).
@export var lean_angle := 15.0

## How quickly the skater leans in when A/D is pressed (higher = snappier).
@export var lean_speed := 8.0

## How quickly the skater returns upright when A/D is released.
@export var lean_return_speed := 14.0

# --- Brake lean (S) ---

## How far the skater leans back (towards the camera) when braking (degrees).
@export var brake_lean_angle := 10.0

## Minimum time the brake lean is held after a tap of S (s).
@export var brake_lean_time := 0.4

## How quickly the brake lean comes in and goes out.
@export var brake_lean_speed := 10.0




# ==============================================================================
#
#   CAMERA  -  framing, follow, arrow-key orbit, -/+ zoom
#
# ==============================================================================

@export_group("CAMERA")

# --- Framing ---

## Default distance behind the player (m at player_scale 1).
@export var camera_distance := 8.0

## Default camera height above the player's ground (m).
@export var camera_height := 3.0

## Height above the player's ground the camera looks at (m).
@export var camera_look_height := 1.2

# --- Follow the skater's turn ---

## The camera starts turning once the skater's heading is more than this far
## off it (degrees). Below this it stays put (dead zone).
@export var camera_follow_start := 20.0

## Hard limit: the camera is never more than this far off the skater's heading
## (degrees). Between start and lock its turn speed ramps linearly from 0 to
## the skater's turn_speed (e.g. 20/30: 21 deg = 10%, 25 deg = 50%, 30 deg = 100%).
@export var camera_follow_lock := 30.0

## Roughly how long the camera takes to re-centre on the travel forward once
## the skater is back within camera_follow_start of it (s). It eases in and out,
## carrying on smoothly from the speed it was already turning at.
@export var camera_recenter_time := 0.8

# --- Orbit (arrow keys) ---

## Arrow-key orbit speed (degrees per second).
@export var camera_orbit_speed := 90.0

## How quickly the camera eases back to default after the arrows are released.
@export var camera_return_speed := 3.0

## Pitch limits of the orbit, as elevation above the look point (degrees).
@export var camera_min_elevation := 2.0
@export var camera_max_elevation := 75.0

## Orbiting left/right also turns the player's movement forward (the camera's
## horizontal look direction), so you can steer briefly; it eases back to the
## path direction as the orbit returns. The camera itself still follows the path.
@export var steer_with_camera := true

## Fraction of the orbit yaw applied to movement (1 = move where the camera looks).
@export var camera_steer_amount := 1.0

# --- Zoom (- / +) ---

## -/+ zoom rate while held (1 = distance changes by a factor of e per second).
@export var camera_zoom_speed := 1.0

## Seconds a zoom is held after -/+ is released before it eases back.
@export var camera_zoom_hold := 5.0

## How quickly the zoom eases back to default after the hold.
@export var camera_zoom_return_speed := 2.0

## Zoom limits, as a multiple of the default distance.
@export var camera_zoom_min := 0.3
@export var camera_zoom_max := 3.0




# ==============================================================================
#
#   PATH AXES  -  which path supplies forward/right, switching at forks
#
# ==============================================================================

@export_group("PATH AXES")

## Another path must be this much closer before it takes over (m).
@export var switch_margin := 0.5

## Width of the zone where axes blend between two paths (m).
@export var blend_distance := 2.0

## Beyond this distance from every path, no path is active (m).
@export var max_path_distance := 20.0

## A second path within this distance of the player makes the choice ambiguous, so
## path following switches off (free roaming). Paths farther than this but inside
## max_path_distance are ignored. Set it equal to max_path_distance for the strict
## "any two paths in range" rule.
@export var path_ambiguity_distance := 10.0




# ==============================================================================
#
#   COLLISIONS  -  small lips, sliding along walls, rebound
#
# ==============================================================================

@export_group("COLLISIONS")

## Lips up to this height above the player's feet are ridden over without slowing
## down: the collision is ignored and the view eases up to the new ground height.
## World metres, not scaled by player_scale (lips belong to the world). Taller things
## are walls. 0 turns stepping off.
@export var step_height := 1.0

## How quickly the view and camera catch up after riding over a lip (higher =
## quicker). The player's body moves up at once; only the view eases.
@export var step_smooth_speed := 18.0

## On hitting a wall the player keeps the part of his speed that runs along it and
## slides frictionlessly, and is pushed this far back off it (m at player_scale 1).
## 0 turns the rebound off.
@export var wall_rebound_distance := 1.0

## A hit has to push into the wall at least this fast to rebound (m/s at
## player_scale 1), so grazing a wall just slides.
@export var wall_rebound_min_speed := 3.0
