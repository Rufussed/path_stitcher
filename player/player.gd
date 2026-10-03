extends CharacterBody3D
## Skateboarding player. Axes come from the PathAxesFollower child; movement is
## free (nothing holds the player to the path). Tuning comes from GameParams
## (select the scene root to edit it).
##
## W: kick. Holding W chains kicks; each kick gives a forward speed impulse at
## `kick_impulse_point` through the animation (0.5 = halfway).
## S (on press): brake impulse; speed never goes below zero (no rolling back).
## The skater leans back while braking.
## Speed fades linearly to zero over `rollout` seconds from the last impulse.
## A/D: strafe left/right relative to the path, lean into it, and turn (yaw)
## the skater while held; the turn snaps back to the forward on release.
## Space: jump.
## Left/Right arrows (camera orbit) also turn the movement forward with
## `steer_with_camera`, easing back to the forward as the orbit returns.
## Turning further than `reverse_angle` makes the path's backward direction the
## forward (backtracking); while backtracking, `forward_return_angle` turns it
## back to the path's official forward.
## Airborne (not on the floor): horizontal velocity stays exactly as it was at
## take-off (no rollout fade, braking, strafing, kicking or turning); only
## gravity and collisions change the motion until landing. A kick in progress
## at take-off fades out to the skate animation over `kick_air_cancel_time`.
##
## `player_scale` scales the model, collider and every speed (and gravity, with
## `scale_gravity`), so a small player moves like a normal-sized person in a
## giant world.

## Two kick layers used alternately, so a chained kick crossfades in over the
## end of the previous one instead of restarting it.
const KICK_SHOTS: Array[StringName] = [&"kick_a_shot", &"kick_b_shot"]

## Current forward speed (m/s, world units), always >= 0.
var speed := 0.0
## Which way along the path counts as forward: +1 official forward, -1 backtracking.
var travel_dir := 1.0
## Current side lean (radians, + = leaning right).
var lean := 0.0
## Current brake lean (radians, + = leaning back towards the camera).
var brake_lean := 0.0
## Current A/D turn away from the forward (radians, + = turned left).
var turn_yaw := 0.0
## True while not on the floor.
var airborne := false
## Heading the camera follows: the travel direction turned by the A/D turn
## (not by camera steering, which comes from the camera itself).
var follow_forward := Vector3.ZERO
var _fade_rate := 0.0
var _s_was_down := false
var _brake_hold := 0.0
var _facing := Basis.IDENTITY
## Movement forward at take-off, held while airborne.
var _air_fwd := Vector3.ZERO
## Seconds since the current kick started; < 0 when not kicking.
var _kick_time := -1.0
var _kick_impulse_given := false
var _kick_length := 1.0
var _kick_layer := 0
var _applied_scale := 1.0
var _base_visual_pos := Vector3.ZERO
var _base_radius := 0.4
var _base_height := 1.8
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var axes: PathAxesFollower = $PathAxesFollower
@onready var visual: Node3D = $Visual
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var capsule: CapsuleShape3D = $CollisionShape3D.shape


func _ready() -> void:
	_facing = visual.global_basis.orthonormalized()
	_base_visual_pos = visual.position
	_base_radius = capsule.radius
	_base_height = capsule.height
	var player := anim_tree.get_node_or_null(anim_tree.anim_player) as AnimationPlayer
	if player:
		if player.has_animation(&"skate"):
			player.get_animation(&"skate").loop_mode = Animation.LOOP_LINEAR
		if player.has_animation(&"kick"):
			_kick_length = player.get_animation(&"kick").length
	_apply_scale(GameParams.get_active().player_scale)


func _physics_process(delta: float) -> void:
	var p := GameParams.get_active()
	var s := maxf(p.player_scale, 0.01)
	if s != _applied_scale:
		_apply_scale(s)
	airborne = not is_on_floor()
	_update_kick(p, s, delta)

	var s_down := Input.is_physical_key_pressed(KEY_S)
	if not airborne:
		if s_down and not _s_was_down:
			speed = maxf(0.0, speed - p.brake_impulse * s)
			_brake_hold = p.brake_lean_time
		speed = maxf(0.0, speed - _fade_rate * delta)
	_s_was_down = s_down
	_brake_hold = maxf(0.0, _brake_hold - delta)

	var g_scale := s if p.scale_gravity else 1.0
	if airborne:
		velocity.y -= gravity * g_scale * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		# Jump height scales with the player either way.
		velocity.y = p.jump_speed * (s if p.scale_gravity else sqrt(s))

	var strafe := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var fwd: Vector3
	if airborne and _air_fwd != Vector3.ZERO:
		# No turning in the air: keep the take-off heading.
		fwd = _air_fwd
	else:
		fwd = _ground_forward(p, strafe, delta)
		_air_fwd = fwd
	var rgt := fwd.cross(Vector3.UP).normalized()

	# On the ground the controls set horizontal velocity; in the air it is left
	# as it was at take-off (move_and_slide only changes it on a collision).
	if not airborne:
		var move := fwd * speed + rgt * strafe * p.strafe_speed * s
		velocity.x = move.x
		velocity.z = move.z
	move_and_slide()

	# A wall takes the speed away rather than letting it build up against it.
	if is_on_wall():
		var rv := get_real_velocity()
		speed = minf(speed, maxf(0.0, Vector3(rv.x, 0.0, rv.z).dot(fwd)))

	# Face along the movement forward, then lean: sideways about the direction
	# of travel (A/D) and backwards about the right axis (braking). Visual's
	# origin is at the feet, so both leans pivot on the board.
	var target_lean := strafe * deg_to_rad(p.lean_angle)
	var rate: float = p.lean_speed if strafe != 0.0 else p.lean_return_speed
	lean = lerpf(lean, target_lean, 1.0 - exp(-rate * delta))
	var braking := s_down or _brake_hold > 0.0
	var target_brake := deg_to_rad(p.brake_lean_angle) if braking else 0.0
	brake_lean = lerpf(brake_lean, target_brake, 1.0 - exp(-p.brake_lean_speed * delta))
	var target := Basis.looking_at(fwd).rotated(Vector3.UP, deg_to_rad(p.model_yaw_offset))
	_facing = _facing.slerp(target, minf(1.0, p.turn_rate * delta)).orthonormalized()
	visual.global_basis = Basis(rgt, brake_lean) * Basis(fwd, lean) * _facing \
			* Basis.from_scale(Vector3.ONE * s)


## Movement forward on the ground: the travel direction along the path, turned
## by the A/D turn and the camera orbit, flipping the travel direction when
## turned far enough round. Also updates `follow_forward` for the camera.
func _ground_forward(p: GameParams, strafe: float, delta: float) -> Vector3:
	# A/D turn: yaw away from the forward while held (D = right), snapping back
	# on release. The limit only stops it growing, so a turn re-expressed by a
	# direction flip is never yanked.
	var turn_limit := deg_to_rad(p.turn_max)
	if strafe != 0.0:
		var next := turn_yaw - strafe * deg_to_rad(p.turn_speed) * delta
		if absf(next) <= turn_limit or absf(next) < absf(turn_yaw):
			turn_yaw = next
	else:
		turn_yaw = lerpf(turn_yaw, 0.0, 1.0 - exp(-p.turn_return_speed * delta))

	# Camera steering adds the orbit yaw.
	var cam := get_node_or_null(^"CameraPivot")
	var steer := p.steer_with_camera and cam != null
	var cam_yaw: float = cam.orbit_yaw * p.camera_steer_amount if steer else 0.0

	# Turned far enough round: the opposite path direction becomes forward. The
	# control that did most of the turning is re-expressed against the new
	# forward, so the actual heading doesn't jump.
	var total := turn_yaw + cam_yaw
	var flip_angle := p.reverse_angle if travel_dir > 0.0 else p.forward_return_angle
	if absf(total) > deg_to_rad(flip_angle):
		travel_dir = -travel_dir
		var turn_sign := signf(total)
		if steer and absf(cam_yaw) > absf(turn_yaw):
			cam.flip_travel(turn_sign)
			cam_yaw = cam.orbit_yaw * p.camera_steer_amount
		else:
			turn_yaw = wrapf(turn_yaw - turn_sign * PI, -PI, PI)

	var base := axes.forward_flat * travel_dir
	follow_forward = base.rotated(Vector3.UP, turn_yaw)
	return base.rotated(Vector3.UP, turn_yaw + cam_yaw)


## Resizes the collider and moves the model's feet to its base; the model
## itself is scaled each frame with its rotation.
func _apply_scale(s: float) -> void:
	_applied_scale = s
	capsule.radius = _base_radius * s
	capsule.height = _base_height * s
	visual.position = _base_visual_pos * s


## Starts kicks while W is held and applies each kick's impulse part-way in.
## A chained kick starts `kick_blend_time` before the current one ends, on the
## other kick layer, so the two crossfade. No kicking while airborne: no new
## kick starts, and a kick in progress at take-off fades out to skate over
## `kick_air_cancel_time` without giving its impulse.
func _update_kick(p: GameParams, s: float, delta: float) -> void:
	if airborne and _kick_time >= 0.0:
		var tree_root := anim_tree.tree_root as AnimationNodeBlendTree
		for shot_name in KICK_SHOTS:
			var shot := tree_root.get_node(shot_name) as AnimationNodeOneShot
			shot.fadeout_time = maxf(p.kick_air_cancel_time, 0.0)
			anim_tree.set(StringName("parameters/%s/request" % shot_name), AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_kick_time = -1.0
		_kick_impulse_given = true
		return

	var blend := clampf(p.kick_blend_time, 0.0, _kick_length * 0.5)
	if _kick_time >= 0.0:
		_kick_time += delta
		if not _kick_impulse_given and _kick_time >= _kick_length * p.kick_impulse_point:
			_kick_impulse_given = true
			if not airborne:
				speed = minf(p.max_speed * s, speed + p.kick_impulse * s)
				_fade_rate = speed / maxf(p.rollout, 0.01)
		if _kick_time >= _kick_length:
			_kick_time = -1.0
	var ready_for_next := _kick_time < 0.0 or (_kick_impulse_given and _kick_time >= _kick_length - blend)
	if Input.is_physical_key_pressed(KEY_W) and ready_for_next and not airborne:
		if _kick_time >= 0.0:
			_kick_layer = 1 - _kick_layer
		var shot := (anim_tree.tree_root as AnimationNodeBlendTree).get_node(KICK_SHOTS[_kick_layer]) as AnimationNodeOneShot
		shot.fadein_time = blend
		shot.fadeout_time = blend
		_kick_time = 0.0
		_kick_impulse_given = false
		anim_tree.set(StringName("parameters/%s/request" % KICK_SHOTS[_kick_layer]), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
