extends Node3D
## Chase camera pivot. Sits at the player's origin and places its Camera3D
## child behind and above the player looking down at it. It follows the
## skater's turns with a dead zone and an eased ramp: no turning until the
## skater is `camera_follow_start` off the camera, then turning faster as the
## gap grows, reaching the skater's own turn speed at `camera_follow_lock`, which
## is a hard limit. Once the skater is back within `camera_follow_start` of the
## travel forward, it re-centres on it, easing in and out over about
## `camera_recenter_time`. Arrow keys orbit around the player; on release the
## orbit eases back to the default view. - / + zoom out / in; a zoom is held for
## `camera_zoom_hold` seconds after release, then eases back. Tuning comes from
## GameParams; distances scale with `player_scale`.

## Height of this pivot above the player's ground (the capsule's half height)
## at player_scale 1.
@export var ground_offset := 0.9

var orbit_yaw := 0.0
var orbit_pitch := 0.0
## Zoom as a log of the distance multiplier (0 = default distance).
var zoom_log := 0.0
var _zoom_idle := 0.0
## Current yaw speed of the pivot (radians per second), carried between the
## follow and re-centre phases so the camera never jerks.
var _yaw_vel := 0.0

@onready var camera: Camera3D = $Camera3D
@onready var axes: PathAxesFollower = $"../PathAxesFollower"


func _physics_process(delta: float) -> void:
	var p := GameParams.get_active()
	var s := maxf(p.player_scale, 0.01)

	_follow_heading(p, delta)

	var yaw_in := float(Input.is_physical_key_pressed(KEY_LEFT)) - float(Input.is_physical_key_pressed(KEY_RIGHT))
	var pitch_in := float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN))
	var orbit_step := deg_to_rad(p.camera_orbit_speed) * delta
	var settle := 1.0 - exp(-p.camera_return_speed * delta)
	orbit_yaw = orbit_yaw + yaw_in * orbit_step if yaw_in != 0.0 else lerpf(orbit_yaw, 0.0, settle)
	orbit_pitch = orbit_pitch + pitch_in * orbit_step if pitch_in != 0.0 else lerpf(orbit_pitch, 0.0, settle)

	_update_zoom(p, delta)

	# Default view: `camera_distance` back, `camera_height` up, looking at the
	# look point; the orbit adds yaw around the player and elevation, the zoom
	# scales the distance, and everything scales with the player.
	var rise := p.camera_height - p.camera_look_height
	var base_elev := atan2(rise, p.camera_distance)
	var radius := Vector2(p.camera_distance, rise).length() * exp(zoom_log) * s
	var elev := clampf(base_elev + orbit_pitch, deg_to_rad(p.camera_min_elevation), deg_to_rad(p.camera_max_elevation))
	orbit_pitch = elev - base_elev
	var offset := Vector3(0.0, sin(elev), cos(elev)).rotated(Vector3.UP, orbit_yaw) * radius

	var look := global_position + Vector3.UP * (p.camera_look_height - ground_offset) * s
	camera.global_position = look + global_basis * offset
	camera.look_at(look)


## Turns the pivot to follow the skater's heading:
## - skater within `camera_follow_start` of the travel forward: re-centre on it
##   with a smooth damp (eases in and out, continuing from the current speed);
## - otherwise turn towards the skater at a speed that ramps linearly from 0
##   (gap = start) to the skater's `turn_speed` (gap = lock);
## - never more than `camera_follow_lock` off the skater's heading.
func _follow_heading(p: GameParams, delta: float) -> void:
	var player := get_parent()
	var travel = player.get(&"travel_dir")
	var base := axes.forward_flat * (float(travel) if travel != null else 1.0)
	var heading = player.get(&"follow_forward")
	if not (heading is Vector3) or heading == Vector3.ZERO:
		heading = base

	var start := deg_to_rad(p.camera_follow_start)
	var lock := maxf(deg_to_rad(p.camera_follow_lock), start + 0.001)

	var turn := 0.0
	if absf(base.signed_angle_to(heading, Vector3.UP)) <= start:
		turn = _smooth_damp_turn(_cam_forward().signed_angle_to(base, Vector3.UP), p.camera_recenter_time, delta)
	else:
		var gap := _cam_forward().signed_angle_to(heading, Vector3.UP)
		var ramp := clampf((absf(gap) - start) / (lock - start), 0.0, 1.0)
		turn = signf(gap) * minf(deg_to_rad(p.turn_speed) * ramp * delta, absf(gap))
		_yaw_vel = turn / maxf(delta, 0.0001)
	global_basis = global_basis.orthonormalized().rotated(Vector3.UP, turn)

	# Hard limit.
	var lag := _cam_forward().signed_angle_to(heading, Vector3.UP)
	if absf(lag) > lock:
		global_basis = Basis.looking_at(heading.rotated(Vector3.UP, -signf(lag) * lock))


## Critically damped approach to an angle `remaining` radians away: returns this
## frame's turn and updates `_yaw_vel`. Starts from the current speed, eases
## to a stop, and settles in roughly `smooth_time` seconds.
func _smooth_damp_turn(remaining: float, smooth_time: float, delta: float) -> float:
	var omega := 2.0 / maxf(smooth_time, 0.01)
	var x := omega * delta
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := -remaining
	var temp := (_yaw_vel + omega * change) * delta
	_yaw_vel = (_yaw_vel - omega * temp) * decay
	return remaining + (change + temp) * decay


func _cam_forward() -> Vector3:
	var f := -global_basis.z
	return Vector3(f.x, 0.0, f.z).normalized()


## Called by the player when its travel direction flips and the camera orbit
## caused it: turns the pivot round with the new forward and re-expresses the
## orbit against it, so the view doesn't jump; the orbit then eases back behind.
func flip_travel(sign_of_turn: float) -> void:
	global_basis = global_basis.rotated(Vector3.UP, PI)
	orbit_yaw = wrapf(orbit_yaw - sign_of_turn * PI, -PI, PI)


func _update_zoom(p: GameParams, delta: float) -> void:
	var zoom_out := Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT)
	var zoom_in := Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_PLUS) \
			or Input.is_physical_key_pressed(KEY_KP_ADD)
	var dir := float(zoom_out) - float(zoom_in)
	if dir != 0.0:
		_zoom_idle = 0.0
		zoom_log = clampf(zoom_log + dir * p.camera_zoom_speed * delta,
				log(maxf(p.camera_zoom_min, 0.01)), log(maxf(p.camera_zoom_max, 0.01)))
	else:
		_zoom_idle += delta
		if _zoom_idle >= p.camera_zoom_hold:
			zoom_log = lerpf(zoom_log, 0.0, 1.0 - exp(-p.camera_zoom_return_speed * delta))
