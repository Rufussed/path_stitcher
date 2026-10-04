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

## A wall rebound pushes off at this decay rate (1/s); its outward speed is set so the
## total push is `wall_rebound_distance`. One rebound per cooldown (s).
const REBOUND_RATE := 10.0
const REBOUND_COOLDOWN := 0.5

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
## The movement forward before the A/D turn: the path's forward (times travel_dir)
## on a path, the free heading in free roam. The camera re-centres on it.
var base_forward := Vector3.ZERO
## True while no single path is in range: forward is just where he is facing.
var free_roam := false
## Left Shift toggles following the path (free roaming when off). Starts off, and
## switches itself off when no single path is in range.
var path_following := false
## The view and camera ease up after the body rides over a lip (negative = they are
## still catching up).
var _step_offset := 0.0
var _cam_base_y := 0.0
## Outward push after hitting a wall (decays), the cooldown before the next one, and
## whether he touched a wall last frame.
var _rebound := Vector3.ZERO
var _rebound_cooldown := 0.0
var _was_on_wall := false
var _free_heading := Vector3.ZERO
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
	var pivot := get_node_or_null(^"CameraPivot")
	if pivot:
		_cam_base_y = pivot.position.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SHIFT and event.location == KEY_LOCATION_LEFT:
		if path_following:
			path_following = false
		elif axes.has_path:
			path_following = true # only when exactly one path is in range



func _physics_process(delta: float) -> void:
	var p := GameParams.get_active()
	var s := maxf(p.player_scale, 0.01)
	if s != _applied_scale:
		_apply_scale(s)
	airborne = not is_on_floor()
	_rebound = _rebound.lerp(Vector3.ZERO, 1.0 - exp(-REBOUND_RATE * delta))
	_rebound_cooldown = maxf(_rebound_cooldown - delta, 0.0)
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
		if _rebound.length_squared() > 0.0001:
			var rn := _rebound.normalized()
			var into := move.dot(rn)
			if into < 0.0:
				move -= rn * into # while pushing off a wall, don't push back into it
		velocity.x = move.x + _rebound.x
		velocity.z = move.z + _rebound.z
		_try_step(p, s, delta)
	var v_before := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	_wall_response(p, s, v_before)


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

	# After riding over a lip the view (and camera) ease up to the new height.
	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-p.step_smooth_speed * delta))
	visual.position.y = _base_visual_pos.y * s + _step_offset
	var pivot := get_node_or_null(^"CameraPivot")
	if pivot:
		pivot.position.y = _cam_base_y + _step_offset


## Movement forward on the ground: the travel direction along the path, turned
## by the A/D turn and the camera orbit, flipping the travel direction when
## turned far enough round. Also updates `follow_forward` for the camera.
func _ground_forward(p: GameParams, strafe: float, delta: float) -> Vector3:
	if path_following and not axes.has_path:
		path_following = false # too far from the paths, or several in range: free roaming
	if not path_following:
		return _free_forward(p, strafe, delta)
	if free_roam:
		# Back on a single path: forward is whichever way along it he is facing.
		free_roam = false
		travel_dir = 1.0 if _free_heading.dot(axes.forward_flat) >= 0.0 else -1.0
		turn_yaw = 0.0
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
	base_forward = base
	follow_forward = base.rotated(Vector3.UP, turn_yaw)
	return base.rotated(Vector3.UP, turn_yaw + cam_yaw)


## Free roam (no path, or more than one, within range): forward is the way he
## is facing. A/D turn that heading for good (no snap-back); the camera orbit
## steering still adds its temporary turn.
func _free_forward(p: GameParams, strafe: float, delta: float) -> Vector3:
	if not free_roam:
		free_roam = true
		_free_heading = _facing_forward(p)
		turn_yaw = 0.0
	if strafe != 0.0:
		_free_heading = _free_heading.rotated(Vector3.UP, -strafe * deg_to_rad(p.turn_speed) * delta)
	var cam := get_node_or_null(^"CameraPivot")
	var cam_yaw: float = cam.orbit_yaw * p.camera_steer_amount if (p.steer_with_camera and cam != null) else 0.0
	base_forward = _free_heading
	follow_forward = _free_heading
	return _free_heading.rotated(Vector3.UP, cam_yaw)


## The horizontal direction the skater is currently facing.
func _facing_forward(p: GameParams) -> Vector3:
	var f := -(Basis(Vector3.UP, -deg_to_rad(p.model_yaw_offset)) * _facing).z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


## Lets him ride over a small lip in his way (up to `step_height`): the body moves
## up at once and the horizontal speed is untouched; only the view eases up, via
## `_step_offset`.
func _try_step(p: GameParams, s: float, delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if p.step_height <= 0.0 or h.length() < 0.05:
		return
	var motion := h * delta
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit) or hit.get_normal().y > 0.7:
		return # nothing in the way, or a slope he can simply walk up
	var max_up := p.step_height * s
	var raised := global_transform.translated(Vector3.UP * max_up)
	if test_move(raised, motion):
		return # taller than the step height: a real wall
	var down := KinematicCollision3D.new()
	if not test_move(raised.translated(motion), Vector3.DOWN * max_up * 1.02, down):
		return # nothing to stand on past the lip
	var rise := clampf(max_up - down.get_travel().length() + 0.002, 0.0, max_up)
	if rise <= 0.0:
		return
	global_position.y += rise
	_step_offset -= rise


## After moving: a wall keeps the part of his speed that runs along it (the engine
## slides him, frictionless), a near head-on hit takes his speed away so it can't
## build up against the wall, and a hard enough first hit pushes him back off it
## by `wall_rebound_distance` (once per `REBOUND_COOLDOWN`).
func _wall_response(p: GameParams, s: float, v_before: Vector3) -> void:
	var touching := false
	var n_best := Vector3.ZERO
	var inward_best := 0.0
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y > 0.7:
			continue # floor
		var nh := Vector3(n.x, 0.0, n.z)
		if nh.length() < 0.001:
			continue
		touching = true
		nh = nh.normalized()
		var inward := -v_before.dot(nh)
		if inward > inward_best:
			inward_best = inward
			n_best = nh
	var first_contact := touching and not _was_on_wall
	_was_on_wall = touching
	if not first_contact or inward_best <= 0.0:
		return
	var vlen := v_before.length()
	if vlen > 0.001:
		var along := (v_before + n_best * inward_best).length() # the part along the wall
		if along < 0.25 * vlen:
			speed = minf(speed, along)
	if p.wall_rebound_distance > 0.0 and not airborne and _rebound_cooldown <= 0.0 \
			and inward_best >= p.wall_rebound_min_speed * s:
		# An outward speed that decays at REBOUND_RATE covers about the set distance.
		_rebound = n_best * p.wall_rebound_distance * s * REBOUND_RATE
		_rebound_cooldown = REBOUND_COOLDOWN



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
