@tool
class_name PathSpiral
extends Path3D
## A Path3D that builds its own curve as a spiral, so you can reshape it from
## the Inspector instead of editing points by hand. Change any value below and
## the curve is rebuilt; a PathStitcher on this path follows it live. Optional:
## any Path3D works with a PathStitcher.
##
## The path runs counter-clockwise seen from above, so the outside of the turn
## is the path's left (+Z of a block). Each turn climbs `rise_per_turn`; set it
## to your block height so every turn rests on the one below.

## Number of full turns (fractions allowed).
@export_range(0.25, 20.0, 0.25, "or_greater") var turns := 3.5:
	set(v):
		turns = v
		_queue_build()

## Radius at the start of the path.
@export_range(1.0, 500.0, 0.5, "or_greater", "suffix:m") var start_radius := 32.0:
	set(v):
		start_radius = v
		_queue_build()

## Radius at the end of the path. Smaller than the start makes a tapering tower.
@export_range(1.0, 500.0, 0.5, "or_greater", "suffix:m") var end_radius := 14.0:
	set(v):
		end_radius = v
		_queue_build()

## Height gained per full turn. Negative winds the path downwards.
@export_range(-200.0, 200.0, 0.5, "or_greater", "or_less", "suffix:m") var rise_per_turn := 16.0:
	set(v):
		rise_per_turn = v
		_queue_build()

## Curve points per turn. More points follow the circle more closely.
@export_range(6, 96, 1, "or_greater") var points_per_turn := 24:
	set(v):
		points_per_turn = maxi(v, 6)
		_queue_build()

## Rebuild the curve now.
@export_tool_button("Rebuild curve", "Reload") var rebuild_action = build

var _queued := false


func _ready() -> void:
	if curve == null or curve.point_count < 2:
		build()


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
	for i in count + 1:
		var t := step * i
		var r := start_radius + dr * t
		var p := Vector3(r * cos(t), dh * t, r * sin(t))
		# Bezier handles from the exact derivative, so the curve is smooth.
		var d := Vector3(dr * cos(t) - r * sin(t), dh, dr * sin(t) + r * cos(t)) * (step / 3.0)
		c.add_point(p, -d, d)
	curve = c
