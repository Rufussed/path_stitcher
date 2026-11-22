class_name PathAxesFollower
extends Node
## Supplies movement axes from the nearest Path3D in `group` to the parent
## Node3D. Forward runs along the curve (increasing offset), right is
## horizontal and perpendicular. It never moves the parent itself.
##
## Near a fork the active path only changes once another path is closer by
## `switch_margin`, and within `blend_distance` the axes blend between the two.

signal path_changed(path: Path3D)

@export var group := "movement_paths"
@export var switch_margin := 0.5
@export var blend_distance := 2.0
@export var max_distance := 20.0
## A second path this close to the player makes the choice ambiguous (free roaming).
@export var ambiguity_distance := 10.0

var forward := Vector3.FORWARD
var forward_flat := Vector3.FORWARD
var right := Vector3.RIGHT
var up := Vector3.UP
var path: Path3D
## Position in path coordinates: px along the path, py height above the
## path point, pz sideways offset (+ = left of travel). See the spec.
var path_coords := Vector3.ZERO
var distance := INF
var has_path := false


func _physics_process(_delta: float) -> void:
	var owner_3d := get_parent() as Node3D
	if owner_3d:
		update_axes(owner_3d.global_position)


func update_axes(pos: Vector3) -> void:
	var samples := []
	for p in get_tree().get_nodes_in_group(group):
		if p is Path3D and p.curve and p.curve.point_count > 1 and p.is_visible_in_tree(): # a hidden path is ignored
			var smp := sample(p, pos)
			if smp.distance <= max_distance:
				samples.append(smp)
	samples.sort_custom(func(a, b): return a.distance < b.distance)
	# Free roam: no path in range, or a second one close enough to make the choice ambiguous.
	if samples.is_empty() or (samples.size() > 1 and samples[1].distance <= ambiguity_distance):
		has_path = false
		path = null # so the next path found defines forward afresh
		return
	samples.sort_custom(func(a, b): return a.distance < b.distance)

	var primary: Dictionary = samples[0]
	for smp in samples:
		if smp.path == path and smp.distance - primary.distance < switch_margin:
			primary = smp
			break
	# Keep "forward" meaning the way we were going when changing path.
	# Only when switching from a path we were already on; the first path found defines forward.
	if path != null and primary.path != path and primary.forward.dot(forward) < 0.0:
		_flip(primary)

	var f: Vector3 = primary.forward
	var ff: Vector3 = primary.forward_flat
	for smp in samples:
		if smp.path == primary.path:
			continue
		var gap: float = smp.distance - primary.distance
		if gap < blend_distance:
			if smp.forward.dot(f) < 0.0:
				_flip(smp)
			var w := 0.5 * (1.0 - maxf(gap, 0.0) / blend_distance)
			f = f.lerp(smp.forward, w).normalized()
			ff = ff.lerp(smp.forward_flat, w).normalized()
		break

	forward = f
	forward_flat = ff
	right = ff.cross(Vector3.UP).normalized()
	path_coords = primary.path_coords
	distance = primary.distance
	has_path = true
	if primary.path != path:
		path = primary.path
		path_changed.emit(path)


## Axes of one path at world position pos.
static func sample(p: Path3D, pos: Vector3) -> Dictionary:
	var c := p.curve
	var length := c.get_baked_length()
	var s := c.get_closest_offset(p.global_transform.affine_inverse() * pos)
	var a := c.sample_baked(maxf(s - 0.1, 0.0), true)
	var b := c.sample_baked(minf(s + 0.1, length), true)
	var f := (p.global_basis * (b - a)).normalized()
	var ff := Vector3(f.x, 0.0, f.z).normalized()
	var r := ff.cross(Vector3.UP).normalized()
	var closest := p.global_transform * c.sample_baked(s, true)
	return {
		"path": p,
		"forward": f,
		"forward_flat": ff,
		"path_coords": Vector3(s, pos.y - closest.y, (pos - closest).dot(-r)),
		"distance": pos.distance_to(closest),
	}


static func _flip(smp: Dictionary) -> void:
	smp.forward = -smp.forward
	smp.forward_flat = -smp.forward_flat
