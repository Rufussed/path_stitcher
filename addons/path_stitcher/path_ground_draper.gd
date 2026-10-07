@tool
class_name PathGroundDraper
extends Node
## Drapes a Path3D onto the ground below it. Each curve point is ray-cast
## straight down onto physics collision: its height becomes the hit height plus
## `height_offset`, and (with `bank_to_ground`) its tilt is set so the curve's
## up vector matches the ground normal across the path. Use it with
## PathStitcher's up_mode PATH so modules lie on the terrain.
##
## Generated modules (anything under a "_Generated" node) are ignored, so a road
## never drapes onto itself. The change is one undoable editor action.

@export_node_path("Path3D") var path_node: NodePath = ^".."
## Re-space the points evenly along the path first (metres); 0 keeps the points.
@export var resample_spacing := 8.0
## Height of the path above the ground.
@export var height_offset := 0.0
## Set point tilt from the ground normal (banking across slopes).
@export var bank_to_ground := true
## Rays start this far above the highest point of the path.
@export var ray_height := 100.0
@export_flags_3d_physics var ground_mask := 1

@export_tool_button("Drape", "CurveTexture") var drape_action = drape


func drape() -> void:
	var p := get_node_or_null(path_node) as Path3D
	if p == null or p.curve == null or p.curve.point_count < 2:
		push_warning("PathGroundDraper: no Path3D with at least 2 points")
		return
	var old := p.curve
	var c := old.duplicate() as Curve3D

	if resample_spacing > 0.0:
		var length := old.get_baked_length()
		var n := maxi(1, roundi(length / resample_spacing))
		var pts := PackedVector3Array()
		for i in n + 1:
			pts.append(old.sample_baked(length * i / n, true))
		c.clear_points()
		for v in pts:
			c.add_point(v)

	var space := p.get_world_3d().direct_space_state
	var top := -INF
	for i in c.point_count:
		top = maxf(top, (p.global_transform * c.get_point_position(i)).y)

	var normals := []
	for i in c.point_count:
		var local := c.get_point_position(i)
		var world := p.global_transform * local
		var hit := _ground(space, Vector3(world.x, top + ray_height, world.z))
		if hit.is_empty():
			normals.append(Vector3.UP)
			continue
		world.y = hit.position.y + height_offset
		c.set_point_position(i, p.global_transform.affine_inverse() * world)
		normals.append(hit.normal)

	# Smooth Catmull-Rom handles through the new points.
	var last := c.point_count - 1
	for i in c.point_count:
		var prev := c.get_point_position(maxi(i - 1, 0))
		var nxt := c.get_point_position(mini(i + 1, last))
		var hnd := (nxt - prev) / (3.0 if i == 0 or i == last else 6.0)
		c.set_point_in(i, -hnd)
		c.set_point_out(i, hnd)
		c.set_point_tilt(i, 0.0)

	if bank_to_ground:
		var to_local := p.global_basis.inverse()
		for i in c.point_count:
			var s := c.get_closest_offset(c.get_point_position(i))
			var t := (c.sample_baked(s + 0.1, true) - c.sample_baked(s - 0.1, true)).normalized()
			var up0 := c.sample_baked_up_vector(s, false)
			var n: Vector3 = (to_local * normals[i]).normalized()
			var np := (n - t * n.dot(t)).normalized()
			c.set_point_tilt(i, atan2(t.dot(up0.cross(np)), up0.dot(np)))

	if Engine.is_editor_hint():
		var ur := EditorInterface.get_editor_undo_redo()
		ur.create_action("Drape path onto ground")
		ur.add_do_property(p, "curve", c)
		ur.add_undo_property(p, "curve", old)
		ur.commit_action()
	else:
		p.curve = c
	print("PathGroundDraper: draped %d points" % c.point_count)


## First ground hit straight down from `from`, skipping generated modules.
func _ground(space: PhysicsDirectSpaceState3D, from: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (ray_height * 4.0 + 1000.0), ground_mask)
	var exclude: Array[RID] = []
	for _attempt in 16:
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not _is_generated(hit.collider):
			return hit
		exclude.append(hit.rid)
	return {}


func _is_generated(node: Node) -> bool:
	while node:
		if node.name == &"_Generated":
			return true
		node = node.get_parent()
	return false
