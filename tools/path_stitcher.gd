@tool
class_name PathStitcher
extends Node3D
## Stitches modules along one Path3D: it lays them end to end and bends every
## vertex through the curve, so neighbouring modules meet seamlessly at shared
## joints instead of being placed as rigid copies with gaps and lips.
##
## Add it as a child of the Path3D it follows: Path Node is then filled in
## automatically (to the parent). Or put it anywhere and set `path_node`.
##
## What is placed comes from `sequence` (a PathSequence): an optional first
## block, a block sequence (repeated in order or a seeded random draw), an
## optional last block, and markers. Edit it in the BUILDING BLOCK SEQUENCE
## section of the Inspector (the PathStitcher editor plugin).
##
## Module axes: X = along the path (px), Y = up (py), Z = lateral (pz), origin
## at the centre of X. A module placed between path distances s0 and s1 maps a
## vertex (x, y, z) to
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
## curve, the path's transform, or a PathMarker on the path changes.

enum UpMode { WORLD, PATH }

## How a block follows the path between its two joints.
## FULL: every vertex is mapped through the curve, so the block bends with it.
## LINEAR: only the block's two end frames are used and the vertices in between
## are blended in a straight line (wedge and shear only, no bend). The seams
## still meet exactly; on tight curves the block cuts across the curve like a chord.
enum Bend { FULL, LINEAR }

## The Path3D to follow. Filled in automatically (to the parent) when this node
## is added under a Path3D; an empty value also means "the parent".
@export_node_path("Path3D") var path_node: NodePath:
	set(value):
		path_node = value
		update_configuration_warnings()
		queue_rebuild()

@export_group("SHAPE")
## How blocks follow the curve.
## Full: bends with the path (organic forms).
## Linear: straight blocks, ends matched - full instancing, GPU optimized.
@export var bend := Bend.FULL:
	set(value):
		bend = value
		queue_rebuild()
## Path distance (m) where the first block starts.
@export var start_offset := 0.0:
	set(value):
		start_offset = value
		queue_rebuild()
## World: walls stay vertical, slopes shear (towers).
## Path: blocks pitch and bank with the path (roads on hills).
@export var up_mode := UpMode.WORLD:
	set(value):
		up_mode = value
		queue_rebuild()
## Swap which side of the path the blocks' +Z side faces.
@export var flip_side := false:
	set(value):
		flip_side = value
		queue_rebuild()

@export_group("")

## What to place along the path (edited in the BUILDING BLOCK SEQUENCE section).
@export var sequence: PathSequence:
	set(value):
		if sequence and sequence.changed.is_connected(queue_rebuild):
			sequence.changed.disconnect(queue_rebuild)
		sequence = value
		if sequence:
			sequence.changed.connect(queue_rebuild)
		update_configuration_warnings()
		queue_rebuild()

@export_tool_button("Rebuild", "Reload") var rebuild_action = rebuild
@export_tool_button("Clear", "Remove") var clear_action = clear

## What the last build placed, and any warnings.
@export_multiline var summary := ""

@export_group("COLLISION")
## Meshes whose name starts with this become invisible collision.
@export var collision_prefix := "Col-":
	set(value):
		collision_prefix = value
		queue_rebuild()
## Meshes whose name starts with this are visible and also become collision.
@export var visible_collision_prefix := "ColVis-":
	set(value):
		visible_collision_prefix = value
		queue_rebuild()
@export var generate_collision := true:
	set(value):
		generate_collision = value
		queue_rebuild()

@export_group("OUTPUT")
## Modules combined into each output mesh and collision body (1 = one per module).
@export_range(1, 100) var chunk_size := 10:
	set(value):
		chunk_size = value
		queue_rebuild()

const STEP := 0.05 # lookup-table resolution along module X, metres
const OUT_NAME := "_Generated"
const SLOTS := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
		Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]

## The path being followed: `path_node`, or the parent when that is empty.
var path: Path3D:
	get:
		if path_node.is_empty():
			return get_parent() as Path3D
		return get_node_or_null(path_node) as Path3D

## Per build: prepared module data [{groups, x0, x1, length, name}] and the
## PathModule -> index map.
var _mods: Array = []
var _mod_index := {}
var _warnings: PackedStringArray = []
var _pending := -1.0
var _poll := 0.0
var _watch_sig := ""
var _shader_cache := {} # cull mode -> instancing Shader


func _enter_tree() -> void:
	# Spell the parent out as the path, so the Inspector shows it assigned.
	if Engine.is_editor_hint() and path_node.is_empty() and get_parent() is Path3D:
		path_node = NodePath("..")


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	update_configuration_warnings()
	rebuild()
	_watch_sig = _watch_signature()


func _validate_property(property: Dictionary) -> void:
	if property.name == "summary":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


## Shown as a warning triangle on the node in the Scene dock.
func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	var p := path
	if p == null:
		out.append("No path: make this node a child of a Path3D, or set Path Node.")
	elif p.curve == null:
		out.append("The Path3D has no curve.")
	elif get_parent() == p and not p.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE):
		out.append("The parent Path3D is scaled, and the blocks inherit its scale. Keep the path's scale at 1, or move this node out of the path.")
	if sequence == null:
		out.append("No building blocks: use Create building blocks in the Inspector.")
	return out


## Schedules a rebuild shortly (editor only), so a burst of edits rebuilds once.
func queue_rebuild() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		_pending = 0.3
		set_process(true)


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
			update_configuration_warnings()
			queue_rebuild()


## Changes to the curve, the path's transform, or PathMarkers on the path, as a
## string to compare.
func _watch_signature() -> String:
	var p := path
	if p == null or p.curve == null:
		return ""
	var parts := [p.curve.get_instance_id(), p.curve.point_count, p.curve.get_baked_length(), p.global_transform]
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

	var instanced := bend == Bend.LINEAR # eligible meshes are drawn by GPU instancing
	var inst_rows := {} # module index -> frames per placement
	var n_chunks := 0
	for c0 in range(0, items.size(), chunk_size):
		var by_key := {} # [material, collider, visible] -> {material, list}
		var faces := PackedVector3Array()
		for i in range(c0, mini(c0 + chunk_size, items.size())):
			var it: Dictionary = items[i]
			var mod: Dictionary = _mods[it.mod]
			var scale_x: float = (it.s1 - it.s0) / mod.stretch_base
			var centre: float = (it.s0 + it.s1) * 0.5
			var x0: float = mod.x0
			var x1: float = mod.x1
			var step := STEP
			if bend == Bend.LINEAR:
				# Two frames, at the block's joints; the blend extends past them.
				x0 = -mod.stretch_base * 0.5
				x1 = mod.stretch_base * 0.5
				step = x1 - x0
			var n_tbl := maxi(2, ceili((x1 - x0) / step) + 1)
			var tbl_p := PackedVector3Array()
			var tbl_l := PackedVector3Array()
			var tbl_u := PackedVector3Array()
			tbl_p.resize(n_tbl)
			tbl_l.resize(n_tbl)
			tbl_u.resize(n_tbl)
			for k in n_tbl:
				var f := _frame(curve, length, xf, centre + (x0 + k * step) * scale_x)
				tbl_p[k] = f[0]
				tbl_l[k] = f[1]
				tbl_u[k] = f[2]
			if instanced:
				var frames: PackedVector3Array = inst_rows.get(it.mod, PackedVector3Array())
				frames.append_array(PackedVector3Array([tbl_p[0], tbl_l[0], tbl_u[0], tbl_p[1], tbl_l[1], tbl_u[1]]))
				inst_rows[it.mod] = frames
			for g in mod.groups:
				if instanced and g.gpu and not g.collider:
					continue # drawn by GPU instancing, nothing to deform here
				var arr := _deform(g.arrays, tbl_p, tbl_l, tbl_u, x0, step)
				if g.collider:
					faces.append_array(_faces(arr))
				if g.visible and not (instanced and g.gpu):
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

	var inst_sets := _build_instances(out, inst_rows) if instanced else 0
	summary = _summarise(items, n_chunks, Time.get_ticks_msec() - t0)
	if inst_sets > 0:
		summary = summary.replace(", %d chunks" % n_chunks, ", %d chunks, %d GPU-instanced meshes" % [n_chunks, inst_sets])
	print("PathStitcher %s: %s" % [name, summary.get_slice("\n", 0)])


## The auto length (m) of a module: its mesh extent along the path minus the
## overlap at both ends. For the Inspector; 0 if it has no usable meshes.
func measure_length(pm: PathModule) -> float:
	if pm == null or pm.scene == null:
		return 0.0
	var root := pm.scene.instantiate()
	var data := _prepare_quiet(root)
	root.free()
	if data.is_empty():
		return 0.0
	var x0: float = data.x0
	var x1: float = data.x1
	return (x1 - x0) - 2.0 * pm.overlap


# ------------------------------------------------------------------------------
# Layout: what goes where along the path
# ------------------------------------------------------------------------------


## Returns the placed modules, in path order: [{mod, s0, s1}], where `mod`
## indexes `_mods` and s0/s1 are the module's joints (path distances).
func _layout(length: float) -> Array:
	if sequence == null:
		_warnings.append("No building blocks set.")
		return []

	var seq := sequence
	var gen := _Gen.new(seq, self)
	var a := start_offset
	var b := length
	var lead: Array = []
	var trail: Array = []
	var fixed: Array = []
	if seq.start and _module(seq.start) >= 0:
		for _i in seq.start_count:
			lead.append(_module(seq.start))
	if seq.end and _module(seq.end) >= 0:
		var e := _module(seq.end)
		var e_len: float = _mods[e].length
		if seq.anchor_end:
			# The last blocks sit unstretched against the path end.
			var pos := b
			for _i in seq.end_count:
				fixed.push_front({"mod": e, "s0": pos - e_len, "s1": pos})
				pos -= e_len
			b = pos
		else:
			for _i in seq.end_count:
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


## Fills [a, b] with `lead` modules, then middle modules from `gen`, then
## `trail` modules, made to fit by the sequence's fit mode. Advances `gen` by
## the middle modules used.
func _fill(a: float, b: float, lead: Array, trail: Array, gen: _Gen) -> Array:
	var span := b - a
	if span <= 0.001:
		if not (lead.is_empty() and trail.is_empty()):
			_warnings.append("A segment of %.2f m is too short for its first/last blocks." % span)
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
			data.stretch_base = data.length # mesh scale along the path is (joint span) / stretch_base
			if pm.stretch_to_length and pm.length > 0.0 and (x1 - x0) - 2.0 * pm.overlap > 0.001:
				data.stretch_base = (x1 - x0) - 2.0 * pm.overlap # stretch the mesh itself to the set length
			if data.length <= 0.001:
				_warnings.append("%s has no length; set its length." % pm.display_name())
			else:
				if pm.offset_py != 0.0 or pm.offset_pz != 0.0:
					var shift := Vector3(0.0, pm.offset_py, pm.offset_pz)
					for g in data.groups:
						var v: PackedVector3Array = g.arrays[Mesh.ARRAY_VERTEX]
						for i in v.size():
							v[i] += shift
						g.arrays[Mesh.ARRAY_VERTEX] = v
				idx = _mods.size()
				_mods.append(data)
	else:
		_warnings.append("A block has no scene set.")
	_mod_index[pm] = idx
	return idx


## Merged mesh data for a module root: {groups, x0, x1, name}, or {} if empty.
func _prepare(root: Node, display: String) -> Dictionary:
	var data := _prepare_quiet(root)
	if data.is_empty():
		_warnings.append("%s has no meshes." % display)
		return {}
	data.name = display
	return data


func _prepare_quiet(root: Node) -> Dictionary:
	var groups := _collect(root)
	if groups.is_empty():
		return {}
	var x0 := INF
	var x1 := -INF
	for g in groups:
		for v in g.arrays[Mesh.ARRAY_VERTEX]:
			x0 = minf(x0, v.x)
			x1 = maxf(x1, v.x)
	return {"groups": groups, "x0": x0, "x1": x1, "name": "", "length": x1 - x0}


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
				"collider": g.collider, "visible": g.visible, "gpu": _gpu_ok(g.material)})
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


# ------------------------------------------------------------------------------
# GPU instancing (Bend: Linear)
# ------------------------------------------------------------------------------

## Shader for instanced blocks: the same straight blend between a block's two
## end frames as the CPU path (Bend: Linear), done per vertex on the GPU. Each
## instance reads its frames (position, left, up at the start and end joint)
## from a small float texture, indexed by INSTANCE_ID. CULL is replaced below.
const INSTANCE_SHADER := """shader_type spatial;
render_mode CULL;

uniform sampler2D path_data : filter_nearest, repeat_disable;
uniform float half_len = 2.5;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform float normal_scale = 1.0;
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D metallic_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

void vertex() {
	int id = INSTANCE_ID;
	vec3 p0 = texelFetch(path_data, ivec2(0, id), 0).xyz;
	vec3 l0 = texelFetch(path_data, ivec2(1, id), 0).xyz;
	vec3 u0 = texelFetch(path_data, ivec2(2, id), 0).xyz;
	vec3 p1 = texelFetch(path_data, ivec2(3, id), 0).xyz;
	vec3 l1 = texelFetch(path_data, ivec2(4, id), 0).xyz;
	vec3 u1 = texelFetch(path_data, ivec2(5, id), 0).xyz;
	float span = 2.0 * half_len;
	float w = (VERTEX.x + half_len) / span;
	vec3 L = normalize(mix(l0, l1, w));
	vec3 U = normalize(mix(u0, u1, w));
	vec3 dx = ((p1 - p0) + (l1 - l0) * VERTEX.z + (u1 - u0) * VERTEX.y) / span;
	mat3 J = mat3(dx, U, L);
	VERTEX = mix(p0, p1, w) + L * VERTEX.z + U * VERTEX.y;
	NORMAL = normalize(transpose(inverse(J)) * NORMAL);
	TANGENT = normalize(J * TANGENT);
	BINORMAL = normalize(J * BINORMAL);
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo;
	ALBEDO = a.rgb;
	ROUGHNESS = roughness * dot(texture(roughness_tex, UV), roughness_channel);
	METALLIC = metallic * dot(texture(metallic_tex, UV), metallic_channel);
	SPECULAR = specular;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).xyz;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
"""


## True if a material is plain enough for the instancing shader (opaque, an
## albedo colour and texture, an optional normal map, roughness and metallic
## values). Anything fancier stays on the CPU path so it still looks right.
func _gpu_ok(mat: Material) -> bool:
	var m := mat as StandardMaterial3D
	if m == null:
		return false
	return m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			and m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			and m.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED \
			and m.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED \
			and not (m.emission_enabled or m.uv1_triplanar or m.vertex_color_use_as_albedo \
			or m.ao_enabled or m.rim_enabled or m.clearcoat_enabled or m.anisotropy_enabled \
			or m.heightmap_enabled or m.subsurf_scatter_enabled or m.backlight_enabled
			or m.refraction_enabled or m.detail_enabled or m.proximity_fade_enabled)


## The instancing shader material for `mat`, reading frames from `data`.
func _gpu_material(mat: StandardMaterial3D, data: Texture2D, half_len: float) -> ShaderMaterial:
	var cull := "cull_disabled"
	if mat.cull_mode == BaseMaterial3D.CULL_BACK:
		cull = "cull_back"
	elif mat.cull_mode == BaseMaterial3D.CULL_FRONT:
		cull = "cull_front"
	if not _shader_cache.has(cull):
		var sh := Shader.new()
		sh.code = INSTANCE_SHADER.replace("CULL", cull)
		_shader_cache[cull] = sh
	var sm := ShaderMaterial.new()
	sm.shader = _shader_cache[cull]
	sm.set_shader_parameter("path_data", data)
	sm.set_shader_parameter("half_len", half_len)
	sm.set_shader_parameter("albedo", mat.albedo_color)
	sm.set_shader_parameter("albedo_tex", mat.albedo_texture)
	sm.set_shader_parameter("use_normal", mat.normal_enabled and mat.normal_texture != null)
	sm.set_shader_parameter("normal_tex", mat.normal_texture)
	sm.set_shader_parameter("normal_scale", mat.normal_scale)
	sm.set_shader_parameter("roughness", mat.roughness)
	sm.set_shader_parameter("metallic", mat.metallic)
	sm.set_shader_parameter("specular", mat.metallic_specular)
	sm.set_shader_parameter("roughness_tex", mat.roughness_texture)
	sm.set_shader_parameter("roughness_channel", _channel_mask(mat.roughness_texture_channel))
	sm.set_shader_parameter("metallic_tex", mat.metallic_texture)
	sm.set_shader_parameter("metallic_channel", _channel_mask(mat.metallic_texture_channel))
	sm.set_shader_parameter("uv1_scale", mat.uv1_scale)
	sm.set_shader_parameter("uv1_offset", mat.uv1_offset)
	return sm


## Which texture channel(s) a BaseMaterial3D texture-channel setting reads.
func _channel_mask(channel: int) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0, 0, 0, 1)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
			return Vector4(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 0)
	return Vector4(1, 0, 0, 0)


## One MultiMeshInstance3D per (block type, material) for the groups that can
## be instanced. `rows` maps a module index to its frames, six Vector3 per
## placement: position, left, up at the start joint, then at the end joint.
## Returns how many meshes were made.
func _build_instances(out: Node3D, rows: Dictionary) -> int:
	var made := 0
	for mi in rows:
		var mod: Dictionary = _mods[mi]
		var frames: PackedVector3Array = rows[mi]
		var n := frames.size() / 6
		if n == 0:
			continue
		var texels := PackedFloat32Array()
		texels.resize(frames.size() * 4)
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for i in frames.size():
			texels[i * 4] = frames[i].x
			texels[i * 4 + 1] = frames[i].y
			texels[i * 4 + 2] = frames[i].z
			if i % 3 == 0:
				lo = lo.min(frames[i])
				hi = hi.max(frames[i])
		var img := Image.create_from_data(6, n, false, Image.FORMAT_RGBAF, texels.to_byte_array())
		var data := ImageTexture.create_from_image(img)
		var identity := PackedFloat32Array()
		identity.resize(n * 12)
		for i in n:
			identity[i * 12] = 1.0
			identity[i * 12 + 5] = 1.0
			identity[i * 12 + 10] = 1.0
		var gi := 0
		for g in mod.groups:
			if not (g.visible and g.gpu):
				continue
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.arrays)
			mesh.surface_set_material(0, _gpu_material(g.material, data, mod.stretch_base * 0.5))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = n
			mm.buffer = identity
			var inst := MultiMeshInstance3D.new()
			inst.name = "Inst_%s_%d" % [mod.name, gi]
			inst.multimesh = mm
			# The instances' own transforms are identity, so Godot cannot know where
			# the geometry ends up: give it the bounds of the path part used.
			inst.custom_aabb = AABB(lo, hi - lo).grow(mesh.get_aabb().get_longest_axis_size())
			out.add_child(inst)
			gi += 1
			made += 1
	return made



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


func _deform(src: Array, tbl_p: PackedVector3Array, tbl_l: PackedVector3Array, tbl_u: PackedVector3Array, x0: float, step: float) -> Array:
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
		var f := (v.x - x0) / step
		var k := clampi(int(f), 0, last)
		var w := f - k
		var p := tbl_p[k].lerp(tbl_p[k + 1], w)
		var l := tbl_l[k].lerp(tbl_l[k + 1], w).normalized()
		var u := tbl_u[k].lerp(tbl_u[k + 1], w).normalized()
		out_v[i] = p + l * v.z + u * v.y
		if normals == null and tangents == null:
			continue
		# Jacobian of the mapping: columns d/dx, d/dy, d/dz.
		var dx := (tbl_p[k + 1] - tbl_p[k] + (tbl_l[k + 1] - tbl_l[k]) * v.z + (tbl_u[k + 1] - tbl_u[k]) * v.y) / step
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


## Produces middle modules in order: the block sequence repeated, or a seeded
## weighted random draw (each row's count is its weight). `copy()` lets the
## layout look ahead without consuming.
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
			for e in seq.pattern:
				if e and e.module and e.count > 0 and host._module(e.module) >= 0:
					choices.append(host._module(e.module))
					weights.append(float(e.count))

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
