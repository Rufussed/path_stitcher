@tool
class_name PathSpiral
extends Path3D
## A Path3D that builds its own curve as a spiral, so you can reshape it from
## the Inspector instead of editing points by hand. Change any value below and
## the curve is rebuilt; a PathStitcher on this path follows it live. Optional:
## any Path3D works with a PathStitcher.
##
## The path climbs anticlockwise by default seen from above, like classic Tower
## of Babel pictures, so the outside of the turn is the path's right, which is where
## a block's +Z side faces (see PathStitcher's Flip Side). Each turn climbs `rise_per_turn`; set it
## to your block height so every turn rests on the one below.

@export_group("Spiral")

## Number of full turns (fractions allowed). With snapping on: quarter turns.
@export_range(0.25, 20.0, 0.01, "or_greater") var turns := 3.5:
	set(v):
		turns = maxf(_snapped(v, 0.25), 0.25)
		_value_changed(v, turns)

## Radius at the start of the path.
@export_range(1.0, 500.0, 0.01, "or_greater", "suffix:m") var start_radius := 32.0:
	set(v):
		start_radius = maxf(_snapped(v, snap_step), 1.0)
		_value_changed(v, start_radius)

## Radius at the end of the path. Smaller than the start makes a tapering tower.
@export_range(1.0, 500.0, 0.01, "or_greater", "suffix:m") var end_radius := 14.0:
	set(v):
		end_radius = maxf(_snapped(v, snap_step), 1.0)
		_value_changed(v, end_radius)

## Height gained per full turn. Negative winds the path downwards.
@export_range(-200.0, 200.0, 0.01, "or_greater", "or_less", "suffix:m") var rise_per_turn := 16.0:
	set(v):
		rise_per_turn = _snapped(v, snap_step)
		_value_changed(v, rise_per_turn)

## Curve points per turn. More points follow the circle more closely.
@export_range(6, 96, 1, "or_greater") var points_per_turn := 24:
	set(v):
		points_per_turn = maxi(v, 6)
		_queue_build()

## Which way the path winds, seen from above. Anticlockwise puts the outside of
## the turn on the path's right (where block +Z faces); with Clockwise turn on the
## PathStitcher's Flip Side to keep blocks facing outwards.
@export_enum("Anticlockwise", "Clockwise") var direction := 0:
	set(v):
		direction = v
		_queue_build()

@export_group("Snapping")

## Round the radii and the rise to `snap_step` (and the turns to quarter turns)
## when you change them. Off: any value, down to 0.01.
@export var snap_values := false:
	set(v):
		snap_values = v
		if v and is_node_ready():
			turns = turns # each setter snaps its value and queues a rebuild
			start_radius = start_radius
			end_radius = end_radius
			rise_per_turn = rise_per_turn
			notify_property_list_changed.call_deferred()

## The step the radii and the rise snap to while `snap_values` is on.
@export_range(0.01, 10.0, 0.01, "suffix:m") var snap_step := 0.5:
	set(v):
		snap_step = maxf(v, 0.01)
		if snap_values and is_node_ready():
			snap_values = true

## Rebuild the curve now.
@export_tool_button("Rebuild curve", "Reload") var rebuild_action = build

var _queued := false


func _ready() -> void:
	if curve == null or curve.point_count < 2:
		build()


func _snapped(v: float, step: float) -> float:
	return snappedf(v, step) if snap_values else v


## A value was set; rebuild, and if snapping changed it, refresh the Inspector.
func _value_changed(asked: float, got: float) -> void:
	if not is_equal_approx(asked, got):
		notify_property_list_changed.call_deferred()
	_queue_build()


func _queue_build() -> void:
	if not is_node_ready() or _queued:
		return
	_queued = true
	_run_queued.call_deferred()


func _run_queued() -> void:
	_queued = false
	build()


## Replaces the curve with a spiral built from the settings above.
func build() -> void:
	var c := Curve3D.new()
	var total := turns * TAU
	var step := TAU / float(points_per_turn)
	var count := maxi(int(ceil(total / step)), 1)
	step = total / float(count) # land exactly on the last angle
	var dr := (end_radius - start_radius) / total
	var dh := rise_per_turn / TAU
	var side := 1.0 if direction == 1 else -1.0 # sign of Z: -Z is anticlockwise from above
	for i in count + 1:
		var t := step * i
		var r := start_radius + dr * t
		var p := Vector3(r * cos(t), dh * t, side * r * sin(t))
		# Bezier handles from the exact derivative, so the curve is smooth.
		var d := Vector3(dr * cos(t) - r * sin(t), dh, side * (dr * sin(t) + r * cos(t))) * (step / 3.0)
		c.add_point(p, -d, d)
	curve = c
