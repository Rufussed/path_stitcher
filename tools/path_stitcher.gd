@tool
class_name PathStitcher
extends Node3D
## Stitches modules along one Path3D: it lays them end to end and bends every
## vertex through the curve, so neighbouring modules meet seamlessly at shared
## joints instead of being placed as rigid copies with gaps and lips.
##
## What is placed comes from `sequence` (a PathSequence: start module, a
## repeating pattern or seeded random draw, end module, markers), or, when no
## sequence is set, from `source_node` repeated every `spacing` metres.
##
## Module axes: X = along the path, Y = up, Z = lateral (Z = 0 sits on the
## path), origin at the centre of X. A module placed between path distances
## s0 and s1 maps a vertex (x, y, z) to
##     V = P(s) + z * L(s) + y * U(s),   s = (s0 + s1) / 2 + x * (s1 - s0) / length
## where P is the curve point, L the lateral (left) direction and U the up
## direction. Adjacent modules evaluate the same s at their shared joint, so the
## seams meet exactly even between different module types.
##
## up_mode WORLD: U is world up and L horizontal, so walls stay vertical and
## slope becomes a vertical shear (the tower).
## up_mode PATH: U is perpendicular to the path (Curve3D up vectors, including
## point tilt), so modules pitch and bank with the path (a road on a hill).
##
## For efficiency each module's parts are merged by material once, and
## `chunk_size` consecutive modules are combined into one mesh with one
## collision body, so draw calls scale with chunks x materials.
##
## In the editor the output rebuilds by itself shortly after the sequence, the
## curve, or a PathMarker on the path changes.

enum UpMode { WORLD, PATH }

@export_node_path("Path3D") var path_node: NodePath

## What to place along the path. When empty, `source_node` is repeated every
## `spacing` metres instead.
@export var sequence: PathSequence:
	set(value):
		if sequence and sequence.changed.is_connected(queue_rebuild):
			sequence.changed.disconnect(queue_rebuild)
		sequence = value
		if sequence:
			sequence.changed.connect(queue_rebuild)
		queue_rebuild()

@export_group("Single module (no sequence)")
@export_node_path("Node3D") var source_node: NodePath
## Distance along the path between module centres (joint-to-joint length).
@export var spacing := 5.0
## Adjust the spacing so a whole number of modules exactly fills the path.
@export var stretch_to_fit := false
## Number of modules; 0 fills the whole path.
@export var count := 0
## Hide the source module when the game runs.
@export var hide_source_in_game := true
@export_group("")

## Path distance where the first module's start joint sits.
@export var start_offset := 0.0
## How the module's up direction is chosen; see the class description.
@export var up_mode := UpMode.WORLD
## Flip which side of the path module +Z extends to.
@export var flip_side := false
## Modules combined into each output mesh and collision body (1 = one per module).
@export_range(1, 100) var chunk_size := 10
## Meshes whose name starts with this become invisible collision.
@export var collision_prefix := "Col-"
## Meshes whose name starts with this are visible and also become collision.
@export var visible_collision_prefix := "ColVis-"
@export var generate_collision := true

@export_tool_button("Rebuild", "Reload") var rebuild_action = rebuild
@export_tool_button("Clear", "Remove") var clear_action = clear
@export_tool_button("Add Marker Here", "Marker3D") var add_marker_action = add_marker_here

## What the last build placed, and any warnings.
@export_multiline var summary := ""

const STEP := 0.05 # lookup-table resolution along module X, metres
const OUT_NAME := "_Generated"
const SLOTS := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
		Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]

var path: Path3D:
	get: return get_node_or_null(path_node) as Path3D
var source: Node3D:
	get: return get_node_or_null(source_node) as Node3D

## Per build: prepared module data [{groups, x0, x1, length, name}] and the
## PathModule -> index map.
var _mods: Array = []
var _mod_index := {}
var _warnings: PackedStringArray = []
var _pending := -1.0
var _poll := 0.0
var _watch_sig := ""


func _ready() -> void:
	if not Engine.is_editor_hint() and hide_source_in_game and sequence == null and source:
		source.visible = false
	set_process(Engine.is_editor_hint())
	rebuild()
	_watch_sig = _watch_signature()


func _validate_property(property: Dictionary) -> void:
	if property.name == "summary":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


## Schedules a rebuild shortly (editor only), so a burst of edits rebuilds once.
func queue_rebuild() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		_pending = 0.3


func _process(delta: float) -> void:
	if _pending >= 0.0:
		_pending -= delta
		if _pending < 0.0:
			rebuild()
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		var sig := _watch_signature()
		if sig != _watch_sig:
			_watch_sig = sig
			queue_rebuild()


## Changes to the curve or to PathMarkers on the path, as a string to compare.
func _watch_signature() -> String:
	var p := path
	if p == null or p.curve == null:
		return ""
	var parts := [p.curve.get_instance_id(), p.curve.point_count, p.curve.get_baked_length()]
	for m in _path_markers():
		parts.append([m.position, m.module])
	return str(parts)


func clear() -> void:
	var old := get_node_or_null(OUT_NAME)
	if old:
		remove_child(old)
		old.queue_free()


func rebuild() -> void:
	clear()
	_pending = -1.0
	if path == null or path.curve == null or not is_inside_tree():
		return
	var t0 := Time.get_ticks_msec()
	var curve := path.curve
	var length := curve.get_baked_length()
	var xf := global_transform.affine_inverse() * path.global_transform

	_mods = []
	_mod_index = {}
	_warnings = []
	var items := _layout(length)
	if items.is_empty():
		summary = "Nothing to place.\n" + "\n".join(_warnings)
		return

	var out := Node3D.new()
	out.name = OUT_NAME
	add_child(out) # deliberately unowned: regenerated, never saved into the scene

	var n_chunks := 0
	for c0 in range(0, items.size(), chunk_size):
		var by_key := {} # [material, collider, visible] -> {material, list}
		var faces := PackedVector3Array()
		for i in range(c0, mini(c0 + chunk_size, items.size())):
			var it: Dictionary = items[i]
			var mod: Dictionary = _mods[it.mod]
			var scale_x: float = (it.s1 - it.s0) / mod.length
			var centre: float = (it.s0 + it.s1) * 0.5
			var x0: float = mod.x0
			var x1: float = mod.x1
			var n_tbl := maxi(2, ceili((x1 - x0) / STEP) + 1)
			var tbl_p := PackedVector3Array()
			var tbl_l := PackedVector3Array()
			var tbl_u := PackedVector3Array()
			tbl_p.resize(n_tbl)
			tbl_l.resize(n_tbl)
			tbl_u.resize(n_tbl)
			for k in n_tbl:
				var f := _frame(curve, length, xf, centre + (x0 + k * STEP) * scale_x)
				tbl_p[k] = f[0]
				tbl_l[k] = f[1]
				tbl_u[k] = f[2]
			for g in mod.groups:
				var arr := _deform(g.arrays, tbl_p, tbl_l, tbl_u, x0)
				if g.collider:
					faces.append_array(_faces(arr))
				if g.visible:
					var key := [g.material, g.collider, g.visible]
					if not by_key.has(key):
						by_key[key] = {"material": g.material, "list": []}
					by_key[key].list.append(arr)

		var mesh := ArrayMesh.new()
		for entry in by_key.values():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _concat(entry.list))
			mesh.surface_set_material(mesh.get_surface_count() - 1, entry.material)
		var mi := MeshInstance3D.new()
		mi.name = "Chunk%d" % n_chunks
		mi.mesh = mesh
		out.add_child(mi)
		n_chunks += 1
		if generate_collision and not faces.is_empty():
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			# Single planes (floors, walls) must collide from either side.
			shape.backface_collision = true
			var cs := CollisionShape3D.new()
			cs.shape = shape
			var body := StaticBody3D.new()
			body.add_child(cs)
			mi.add_child(body)

	summary = _summarise(items, n_chunks, Time.get_ticks_msec() - t0)
	print("PathStitcher %s: %s" % [name, summary.get_slice("\n", 0)])


# ------------------------------------------------------------------------------
# Layout: what goes where along the path
# ------------------------------------------------------------------------------


## Returns the placed modules, in path order: [{mod, s0, s1}], where `mod`
## indexes `_mods` and s0/s1 are the module's joints (path distances).
func _layout(length: float) -> Array:
	if sequence == null:
		return _layout_single(length)

	var seq := sequence
	var gen := _Gen.new(seq, self)
	var a := start_offset
	var b := length
	var lead: Array = []
	var trail: Array = []
	var fixed: Array = []
	if seq.start and _module(seq.start) >= 0:
		lead.append(_module(seq.start))
	if seq.end and _module(seq.end) >= 0:
		var e := _module(seq.end)
		var e_len: float = _mods[e].length
		if seq.anchor_end:
			fixed.append({"mod": e, "s0": b - e_len, "s1": b})
			b -= e_len
		else:
			trail.append(e)

	var markers := _all_markers()
	if seq.marker_snap == PathSequence.MarkerSnap.NEAREST_JOINT or markers.is_empty():
		var simple := _fill(a, b, lead, trail, gen)
		if not markers.is_empty():
			_replace_nearest(simple, markers)
		return simple + fixed

	# EXACT markers split the path into segments, each fitted on its own; the
	# generator carries on across them, so the rhythm resumes after a marker.
	var items: Array = []
	var seg_a := a
	var seg_lead := lead
	for mk in markers:
		var m_len: float = _mods[mk.mod].length
		var m0: float = mk.distance - m_len * 0.5
		var m1: float = m0 + m_len
		if m0 < seg_a or m1 > b:
			_warnings.append("Marker %s at %.1f m overlaps the start, the end or another marker; skipped." % [_mods[mk.mod].name, mk.distance])
			continue
		items.append_array(_fill(seg_a, m0, seg_lead, [], gen))
		items.append({"mod": mk.mod, "s0": m0, "s1": m1})
		seg_a = m1
		seg_lead = []
	items.append_array(_fill(seg_a, b, seg_lead, trail, gen))
	return items + fixed


## The original single-module mode: `source_node` every `spacing` metres.
func _layout_single(length: float) -> Array:
	if source == null:
		_warnings.append("No sequence and no source node set.")
		return []
	var data := _prepare(source, "%s" % source.name)
	if data.is_empty():
		return []
	data.length = spacing
	_mods.append(data)
	var available := length - start_offset
	var pitch := spacing
	var n := count if count > 0 else int(available / spacing)
	if stretch_to_fit:
		if count <= 0:
			n = maxi(1, roundi(available / spacing))
		pitch = available / n
	var items := []
	for i in n:
		var s0 := start_offset + pitch * i
		items.append({"mod": 0, "s0": s0, "s1": s0 + pitch})
	return items


## Fills [a, b] with `lead` modules, then middle modules from `gen`, then
## `trail` modules, made to fit by the sequence's fit mode. Advances `gen` by
## the middle modules used.
func _fill(a: float, b: float, lead: Array, trail: Array, gen: _Gen) -> Array:
	var span := b - a
	if span <= 0.001:
		if not (lead.is_empty() and trail.is_empty()):
			_warnings.append("A segment of %.2f m is too short for its start/end modules." % span)
		return []
	var fixed_len := 0.0
	for m in lead + trail:
		fixed_len += _mods[m].length

	var fit := sequence.fit
	var mids: Array = []
	if not gen.is_empty():
		var probe := gen.copy()
		var total := fixed_len
		var overflow := -1
		for _guard in 100000:
			var m := probe.next()
			var m_len: float = _mods[m].length
			if total + m_len > span:
				overflow = m
				break
			mids.append(m)
			total += m_len
		if fit == PathSequence.Fit.FINISH_CYCLE and sequence.mode == PathSequence.Mode.PATTERN:
			var cycle := gen.cycle_length(_mods)
			var cycles := roundi((span - fixed_len) / cycle) if cycle > 0.0 else 0
			if cycles == 0 and fixed_len == 0.0:
				cycles = 1
			mids = []
			probe = gen.copy()
			for _i in cycles * gen.cycle_count():
				mids.append(probe.next())
		elif fit == PathSequence.Fit.STRETCH and overflow >= 0:
			var over_len: float = _mods[overflow].length
			var with_next: float = total + over_len
			if total <= 0.0 or absf(span / with_next - 1.0) < absf(span / total - 1.0):
				mids.append(overflow)
		for _i in mids.size():
			gen.next()

	var order: Array = lead + mids + trail
	if order.is_empty():
		return []
	var items := []
	if fit == PathSequence.Fit.NONE:
		var pos := a
		for m in lead + mids:
			var l: float = _mods[m].length
			items.append({"mod": m, "s0": pos, "s1": pos + l})
			pos += l
		var trail_len := 0.0
		for m in trail:
			trail_len += _mods[m].length
		pos = b - trail_len
		for m in trail:
			var l: float = _mods[m].length
			items.append({"mod": m, "s0": pos, "s1": pos + l})
			pos += l
		return items
	var natural := 0.0
	for m in order:
		natural += _mods[m].length
	var k := span / natural
	if absf(k - 1.0) > 0.1:
		_warnings.append("Stretch %.2f between %.1f m and %.1f m." % [k, a, b])
	var s := a
	for m in order:
		var l: float = _mods[m].length * k
		items.append({"mod": m, "s0": s, "s1": s + l})
		s += l
	return items


## NEAREST_JOINT markers: each replaces the closest module, in its slot.
func _replace_nearest(items: Array, markers: Array) -> void:
	for mk in markers:
		var best := -1
		var best_d := INF
		for i in items.size():
			var c: float = (items[i].s0 + items[i].s1) * 0.5
			if absf(c - mk.distance) < best_d:
				best_d = absf(c - mk.distance)
				best = i
		if best >= 0:
			items[best].mod = mk.mod


## Markers from the sequence and from PathMarker children, sorted by distance:
## [{mod, distance}].
func _all_markers() -> Array:
	var out := []
	for e in sequence.markers:
		if e and e.module and _module(e.module) >= 0:
			out.append({"mod": _module(e.module), "distance": e.distance})
	for m in _path_markers():
		if m.module and _module(m.module) >= 0:
			out.append({"mod": _module(m.module), "distance": m.path_distance()})
	out.sort_custom(func(x, y): return x.distance < y.distance)
	return out


func _path_markers() -> Array:
	var p := path
	if p == null:
		return []
	return p.get_children().filter(func(c): return c is PathMarker)


func _summarise(items: Array, n_chunks: int, ms: int) -> String:
	var counts := {}
	var k_min := INF
	var k_max := -INF
	for it in items:
		var mod: Dictionary = _mods[it.mod]
		counts[mod.name] = counts.get(mod.name, 0) + 1
		var k: float = (it.s1 - it.s0) / mod.length
		k_min = minf(k_min, k)
		k_max = maxf(k_max, k)
	var parts := []
	for n in counts:
		parts.append("%s x%d" % [n, counts[n]])
	var text := "%d modules (%s), stretch %.3f-%.3f, %d chunks, %d ms" % [
			items.size(), ", ".join(parts), k_min, k_max, n_chunks, ms]
	if not _warnings.is_empty():
		text += "\n" + "\n".join(_warnings)
	return text


# ------------------------------------------------------------------------------
# Modules: merged mesh data per module type
# ------------------------------------------------------------------------------


## Index of a PathModule's prepared data in `_mods`, preparing it on first use;
## -1 if it has no usable meshes.
func _module(pm: PathModule) -> int:
	if _mod_index.has(pm):
		return _mod_index[pm]
	var idx := -1
	if pm.scene:
		var root := pm.scene.instantiate()
		var data := _prepare(root, pm.display_name())
		root.free()
		if not data.is_empty():
			var x0: float = data.x0
			var x1: float = data.x1
			data.length = pm.length if pm.length > 0.0 else (x1 - x0) - 2.0 * pm.overlap
			if data.length <= 0.001:
				_warnings.append("%s has no length; set its length." % pm.display_name())
			else:
				idx = _mods.size()
				_mods.append(data)
	else:
		_warnings.append("A module has no scene set.")
	_mod_index[pm] = idx
	return idx


## Merged mesh data for a module root: {groups, x0, x1, name}, or {} if empty.
func _prepare(root: Node, display: String) -> Dictionary:
	var groups := _collect(root)
	if groups.is_empty():
		_warnings.append("%s has no meshes." % display)
		return {}
	var x0 := INF
	var x1 := -INF
	for g in groups:
		for v in g.arrays[Mesh.ARRAY_VERTEX]:
			x0 = minf(x0, v.x)
			x1 = maxf(x1, v.x)
	return {"groups": groups, "x0": x0, "x1": x1, "name": display, "length": x1 - x0}


## Surfaces under `root` baked into root-local space, merged into one set of
## arrays per (material, collider, visible) combination. Works on nodes that
## are not in the tree (instanced module scenes) as well as placed ones.
func _collect(root: Node) -> Array:
	var by_key := {}
	for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		# An empty prefix matches nothing (begins_with("") is always true).
		var col_only := not collision_prefix.is_empty() and m.name.begins_with(collision_prefix)
		var col_vis := not visible_collision_prefix.is_empty() and m.name.begins_with(visible_collision_prefix)
		var rel := _relative_transform(m, root)
		var nb := rel.basis.inverse().transposed()
		for si in m.mesh.get_surface_count():
			if m.mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := m.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in v.size():
				v[i] = rel * v[i]
			arr[Mesh.ARRAY_VERTEX] = v
			if arr[Mesh.ARRAY_NORMAL] != null:
				var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for i in n.size():
					n[i] = (nb * n[i]).normalized()
				arr[Mesh.ARRAY_NORMAL] = n
			if arr[Mesh.ARRAY_TANGENT] != null:
				var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
				for i in t.size() >> 2:
					var tv := (rel.basis * Vector3(t[i * 4], t[i * 4 + 1], t[i * 4 + 2])).normalized()
					t[i * 4] = tv.x
					t[i * 4 + 1] = tv.y
					t[i * 4 + 2] = tv.z
				arr[Mesh.ARRAY_TANGENT] = t
			var mat := m.get_active_material(si)
			var key := [mat, col_only or col_vis, not col_only]
			if not by_key.has(key):
				by_key[key] = {"material": mat, "collider": key[1], "visible": key[2], "list": []}
			by_key[key].list.append(arr)
	var groups := []
	for g in by_key.values():
		groups.append({"arrays": _concat(g.list), "material": g.material,
				"collider": g.collider, "visible": g.visible})
	return groups


## Transform of `node` relative to `root` (root's own transform excluded).
func _relative_transform(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# ------------------------------------------------------------------------------
# Deformation
# ------------------------------------------------------------------------------


## [position, left, up] at path distance s, in this node's space.
## Beyond the path ends the curve is extended along its end tangent.
func _frame(curve: Curve3D, length: float, xf: Transform3D, s: float) -> Array:
	var sc := clampf(s, 0.0, length)
	var e := 0.05
	var tng := (curve.sample_baked(minf(sc + e, length), true) - curve.sample_baked(maxf(sc - e, 0.0), true)).normalized()
	var p := curve.sample_baked(sc, true) + tng * (s - sc)
	var l: Vector3
	var u: Vector3
	if up_mode == UpMode.PATH:
		var raw_up := curve.sample_baked_up_vector(sc, true)
		l = raw_up.cross(tng).normalized()
		u = tng.cross(l).normalized()
	else:
		l = Vector3.UP.cross(Vector3(tng.x, 0.0, tng.z).normalized())
		u = Vector3.UP
	if flip_side:
		l = -l
	return [xf * p, (xf.basis * l).normalized(), (xf.basis * u).normalized()]


func _deform(src: Array, tbl_p: PackedVector3Array, tbl_l: PackedVector3Array, tbl_u: PackedVector3Array, x0: float) -> Array:
	var arr := src.duplicate()
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var normals = src[Mesh.ARRAY_NORMAL]
	var tangents = src[Mesh.ARRAY_TANGENT]
	var out_v := PackedVector3Array()
	out_v.resize(verts.size())
	var out_n := PackedVector3Array()
	var out_t := PackedFloat32Array()
	if normals != null:
		out_n.resize(verts.size())
	if tangents != null:
		out_t = tangents.duplicate()
	var last := tbl_p.size() - 2
	for i in verts.size():
		var v := verts[i]
		var f := (v.x - x0) / STEP
		var k := clampi(int(f), 0, last)
		var w := f - k
		var p := tbl_p[k].lerp(tbl_p[k + 1], w)
		var l := tbl_l[k].lerp(tbl_l[k + 1], w).normalized()
		var u := tbl_u[k].lerp(tbl_u[k + 1], w).normalized()
		out_v[i] = p + l * v.z + u * v.y
		if normals == null and tangents == null:
			continue
		# Jacobian of the mapping: columns d/dx, d/dy, d/dz.
		var dx := (tbl_p[k + 1] - tbl_p[k] + (tbl_l[k + 1] - tbl_l[k]) * v.z + (tbl_u[k + 1] - tbl_u[k]) * v.y) / STEP
		var j := Basis(dx, u, l)
		if normals != null:
			out_n[i] = (j.inverse().transposed() * normals[i]).normalized()
		if tangents != null:
			var t := (j * Vector3(out_t[i * 4], out_t[i * 4 + 1], out_t[i * 4 + 2])).normalized()
			out_t[i * 4] = t.x
			out_t[i * 4 + 1] = t.y
			out_t[i * 4 + 2] = t.z
	arr[Mesh.ARRAY_VERTEX] = out_v
	if normals != null:
		arr[Mesh.ARRAY_NORMAL] = out_n
	if tangents != null:
		arr[Mesh.ARRAY_TANGENT] = out_t
	return arr


## Concatenates surface arrays into one indexed surface. Only attributes every
## input has are kept, so differing source formats merge safely.
func _concat(list: Array) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for slot in SLOTS:
		if list.all(func(a): return a[slot] != null):
			var acc = list[0][slot].duplicate()
			for j in range(1, list.size()):
				acc.append_array(list[j][slot])
			out[slot] = acc
	var idx := PackedInt32Array()
	var base := 0
	for a in list:
		var n: int = a[Mesh.ARRAY_VERTEX].size()
		if a[Mesh.ARRAY_INDEX] == null:
			for k in n:
				idx.append(base + k)
		else:
			for k in a[Mesh.ARRAY_INDEX]:
				idx.append(base + k)
		base += n
	out[Mesh.ARRAY_INDEX] = idx
	return out


func _faces(arr: Array) -> PackedVector3Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	for idx in arr[Mesh.ARRAY_INDEX]:
		out.append(v[idx])
	return out


# ------------------------------------------------------------------------------
# Editor: markers
# ------------------------------------------------------------------------------


## Adds a PathMarker on the path at the point closest to the editor camera,
## as one undoable action, and selects it.
func add_marker_here() -> void:
	var ei = Engine.get_singleton(&"EditorInterface")
	var p := path
	if ei == null or p == null or p.curve == null:
		return
	var cam: Camera3D = ei.get_editor_viewport_3d(0).get_camera_3d()
	var offset := p.curve.get_closest_offset(p.to_local(cam.global_position))
	var marker := PathMarker.new()
	marker.name = "PathMarker"
	marker.position = p.curve.sample_baked(offset, true)
	var ur = ei.get_editor_undo_redo()
	ur.create_action("Add path marker")
	ur.add_do_method(p, "add_child", marker, true)
	ur.add_do_property(marker, "owner", ei.get_edited_scene_root())
	ur.add_do_reference(marker)
	ur.add_undo_method(p, "remove_child", marker)
	ur.commit_action()
	ei.get_selection().clear()
	ei.get_selection().add_node(marker)


# ------------------------------------------------------------------------------
# Sequence generator
# ------------------------------------------------------------------------------


## Produces middle modules in order: the pattern repeated, or a seeded weighted
## random draw. `copy()` lets the layout look ahead without consuming.
class _Gen:
	var mode := 0
	var flat: Array = [] # pattern, expanded: module indexes
	var idx := 0
	var choices: Array = [] # random: module indexes
	var weights: Array = []
	var rng := RandomNumberGenerator.new()
	var max_repeat := 0
	var last := -1
	var run := 0

	func _init(seq: PathSequence = null, host = null) -> void:
		if seq == null:
			return
		mode = seq.mode
		max_repeat = seq.max_repeat
		rng.seed = seq.random_seed
		if mode == PathSequence.Mode.PATTERN:
			for e in seq.pattern:
				if e and e.module and host._module(e.module) >= 0:
					for _i in e.count:
						flat.append(host._module(e.module))
			idx = seq.pattern_offset
		else:
			for e in seq.random_entries:
				if e and e.module and e.weight > 0.0 and host._module(e.module) >= 0:
					choices.append(host._module(e.module))
					weights.append(e.weight)

	func copy() -> _Gen:
		var g := _Gen.new()
		g.mode = mode
		g.flat = flat
		g.idx = idx
		g.choices = choices
		g.weights = weights
		g.rng.seed = rng.seed
		g.rng.state = rng.state
		g.max_repeat = max_repeat
		g.last = last
		g.run = run
		return g

	func is_empty() -> bool:
		return flat.is_empty() if mode == PathSequence.Mode.PATTERN else choices.is_empty()

	func next() -> int:
		var m: int
		if mode == PathSequence.Mode.PATTERN:
			m = flat[idx % flat.size()]
			idx += 1
		else:
			m = _pick(-1)
			if max_repeat > 0 and m == last and run >= max_repeat and choices.size() > 1:
				m = _pick(last)
		run = run + 1 if m == last else 1
		last = m
		return m

	func _pick(exclude: int) -> int:
		var total := 0.0
		for i in choices.size():
			if choices[i] != exclude:
				total += weights[i]
		var r := rng.randf() * total
		for i in choices.size():
			if choices[i] == exclude:
				continue
			r -= weights[i]
			if r <= 0.0:
				return choices[i]
		return choices[choices.size() - 1]

	func cycle_count() -> int:
		return flat.size()

	func cycle_length(mods: Array) -> float:
		var l := 0.0
		for m in flat:
			l += mods[m].length
		return l
