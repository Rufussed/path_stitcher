@tool
extends VBoxContainer
## The BUILDING BLOCKS section of a PathStitcher's Inspector:
##   First block / Last block (the Last block has an "Anchor to end of path"
##   toggle on its own line),
##   a reorderable block sequence (drag the handle; the number is the repeat
##   count, or the weight when Randomize is on; drop scene files onto "Add
##   block" to add them as rows), a small expander per block for
##   length (px), overlap and offset (py, pz), the fit mode,
##   and markers (a block at a path distance).
## Every edit is one undoable editor action.

const FIT_NAMES := ["Stretch", "Truncate pattern", "Finish cycle", "None"]
const SNAP_NAMES := ["Exact", "Nearest joint"]
const LABEL_WIDTH := 84

var _stitcher: PathStitcher
var _ur: EditorUndoRedoManager
var _watched: PathSequence
var _expanded := {}
var _hints := {}
var _build_queued := false
var _own_edit := false


func setup(stitcher: Object) -> void:
	_stitcher = stitcher as PathStitcher
	_ur = EditorInterface.get_editor_undo_redo()
	_ur.version_changed.connect(_on_history_changed)
	add_theme_constant_override("separation", 6)
	_build()


func _exit_tree() -> void:
	if _ur and _ur.version_changed.is_connected(_on_history_changed):
		_ur.version_changed.disconnect(_on_history_changed)
	_watch(null)


# ------------------------------------------------------------------------------
# Building the controls
# ------------------------------------------------------------------------------


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_hints.clear()
	var seq := _stitcher.sequence
	_watch(seq)

	add_child(_header("BUILDING BLOCKS"))
	if seq == null:
		var create := Button.new()
		create.text = "Create building blocks"
		create.pressed.connect(_create_sequence)
		add_child(create)
		return
	add_child(_end_block("First block", &"start"))
	add_child(_end_block("Last block", &"end"))
	add_child(_sequence_section())
	add_child(HSeparator.new())
	add_child(_markers_section())


func _end_block(title: String, prop: StringName) -> Control:
	var seq := _stitcher.sequence
	var pm: PathModule = seq.get(prop)
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := _label(title)
	l.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(l)
	row.add_child(_picker(pm.scene if pm else null, _on_end_scene.bind(prop)))
	if pm:
		row.add_child(_expander(String(prop)))
	if prop == &"end":
		var anchor_row := HBoxContainer.new()
		var gap := Control.new()
		gap.custom_minimum_size.x = LABEL_WIDTH
		anchor_row.add_child(gap)
		var anchor := CheckBox.new()
		anchor.text = "Anchor Last block to end of path"
		anchor.tooltip_text = "Place the Last block exactly at the end of the path, unstretched.\nOnly the blocks before it are fitted."
		anchor.button_pressed = seq.anchor_end
		anchor.toggled.connect(_on_anchor)
		anchor_row.add_child(anchor)
		box.add_child(anchor_row)
	if pm and _expanded.get(String(prop), false):
		box.add_child(_detail(pm))
	return box


func _sequence_section() -> Control:
	var seq := _stitcher.sequence
	var random := seq.mode == PathSequence.Mode.RANDOM
	var box := VBoxContainer.new()

	var head := HBoxContainer.new()
	var title := _label("Block sequence")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var rnd := CheckBox.new()
	rnd.text = "Randomize"
	rnd.tooltip_text = "Off: the blocks repeat in this order, each row repeated by its count.\nOn: blocks are drawn at random; each row's number is its weight."
	rnd.button_pressed = random
	rnd.toggled.connect(_on_randomize)
	head.add_child(rnd)
	box.add_child(head)

	for i in seq.pattern.size():
		box.add_child(_block_row(i, random))

	var add := _DropButton.new()
	add.text = "Add block  (or drop scene files here)"
	add.tooltip_text = "Click to add an empty row, or drag .blend / .glb / .gltf / .tscn files from the FileSystem dock onto this button to add each one as a block."
	add.icon = _icon("Add")
	add.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add.pressed.connect(_add_block)
	add.on_scenes = _add_blocks_from
	box.add_child(add)

	var fit_row := HBoxContainer.new()
	var fl := _label("Fit")
	fl.custom_minimum_size.x = LABEL_WIDTH
	fit_row.add_child(fl)
	var fit := _option(FIT_NAMES, seq.fit)
	fit.tooltip_text = "How the blocks are made to fill the path exactly.\nStretch: whole blocks, all stretched slightly.\nTruncate pattern: as many whole blocks as fit, then stretched.\nFinish cycle: whole cycles of the sequence only.\nNone: no stretching; a gap may remain."
	fit.item_selected.connect(_on_fit)
	fit_row.add_child(fit)
	box.add_child(fit_row)

	if random:
		var r := HBoxContainer.new()
		var sl := _label("Seed")
		sl.custom_minimum_size.x = LABEL_WIDTH
		r.add_child(sl)
		var seed_spin := _spin(seq.random_seed, -2147483648.0, 2147483647.0, 1.0)
		seed_spin.value_changed.connect(_on_int.bind(seq, &"random_seed", "Set seed"))
		r.add_child(seed_spin)
		r.add_child(_label("Max repeat"))
		var rep := _spin(seq.max_repeat, 0.0, 100.0, 1.0)
		rep.tooltip_text = "Longest run of the same block (0 = unlimited)."
		rep.value_changed.connect(_on_int.bind(seq, &"max_repeat", "Set max repeat"))
		r.add_child(rep)
		box.add_child(r)
	return box


func _block_row(i: int, random: bool) -> Control:
	var seq := _stitcher.sequence
	var entry: PathPatternEntry = seq.pattern[i]
	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	panel.add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)

	var handle := _Handle.new()
	handle.kind = "block"
	handle.index = i
	handle.on_drop = _move_block
	row.add_child(handle)
	row.add_child(_picker(entry.module.scene if entry.module else null, _on_entry_scene.bind(entry)))

	var count := _spin(entry.count, 1.0, 1000.0, 1.0)
	count.prefix = "wt " if random else "×"
	count.custom_minimum_size.x = 76
	count.size_flags_horizontal = Control.SIZE_SHRINK_END
	count.tooltip_text = "Weight: how often this block is picked." if random else "How many of this block in a row."
	count.value_changed.connect(_on_int.bind(entry, &"count", "Set block count"))
	row.add_child(count)

	row.add_child(_expander("b%d" % i))
	var del := Button.new()
	del.flat = true
	del.icon = _icon("Remove")
	if del.icon == null:
		del.text = "x"
	del.tooltip_text = "Remove this block"
	del.pressed.connect(_remove_block.bind(i))
	row.add_child(del)

	if entry.module and _expanded.get("b%d" % i, false):
		v.add_child(_detail(entry.module))
	return panel


func _markers_section() -> Control:
	var seq := _stitcher.sequence
	var box := VBoxContainer.new()
	box.add_child(_header("MARKERS"))
	for i in seq.markers.size():
		var entry: PathMarkerEntry = seq.markers[i]
		var row := HBoxContainer.new()
		row.add_child(_picker(entry.module.scene if entry.module else null, _on_entry_scene.bind(entry)))
		row.add_child(_label("at"))
		var dist := _spin(entry.distance, 0.0, 1000000.0, 0.1, " m")
		dist.tooltip_text = "Path distance (px) where the block's centre lands."
		dist.custom_minimum_size.x = 110
		dist.size_flags_horizontal = Control.SIZE_SHRINK_END
		dist.value_changed.connect(_on_spin.bind(entry, &"distance", "Set marker distance"))
		row.add_child(dist)
		var del := Button.new()
		del.flat = true
		del.icon = _icon("Remove")
		if del.icon == null:
			del.text = "x"
		del.tooltip_text = "Remove this marker"
		del.pressed.connect(_remove_marker.bind(i))
		row.add_child(del)
		box.add_child(row)

	var buttons := HBoxContainer.new()
	var add := Button.new()
	add.text = "Add marker"
	add.icon = _icon("Add")
	add.pressed.connect(_add_marker)
	buttons.add_child(add)
	var here := Button.new()
	here.text = "Add marker here"
	here.tooltip_text = "Drop a PathMarker node on the path at the point closest to the editor camera.\nDrag it along the path in the viewport; set its block in its own Inspector."
	here.icon = _icon("Marker3D")
	here.pressed.connect(_stitcher.add_marker_here)
	buttons.add_child(here)
	box.add_child(buttons)

	var snap_row := HBoxContainer.new()
	var sl := _label("Snap")
	sl.custom_minimum_size.x = LABEL_WIDTH
	snap_row.add_child(sl)
	var snap := _option(SNAP_NAMES, seq.marker_snap)
	snap.tooltip_text = "Exact: the marker sits at its distance and the blocks around it are fitted.\nNearest joint: the marker replaces the closest block in the sequence."
	snap.item_selected.connect(_on_snap)
	snap_row.add_child(snap)
	box.add_child(snap_row)
	return box


## Length / overlap / offset controls for one block.
func _detail(pm: PathModule) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	v.add_child(grid)

	grid.add_child(_label("Length (px)"))
	var length := _spin(pm.length, 0.0, 100000.0, 0.01, " m")
	length.tooltip_text = "Joint-to-joint length along the path. 0 = automatic."
	length.value_changed.connect(_on_spin.bind(pm, &"length", "Set block length"))
	grid.add_child(length)
	grid.add_child(_label("Overlap"))
	var overlap := _spin(pm.overlap, 0.0, 1000.0, 0.01, " m")
	overlap.tooltip_text = "Built-in overlap at each end, removed from the automatic length."
	overlap.value_changed.connect(_on_spin.bind(pm, &"overlap", "Set block overlap"))
	grid.add_child(overlap)
	grid.add_child(_label("Offset py"))
	var py := _spin(pm.offset_py, -100000.0, 100000.0, 0.01, " m")
	py.tooltip_text = "Raise or lower this block."
	py.value_changed.connect(_on_spin.bind(pm, &"offset_py", "Set block py offset"))
	grid.add_child(py)
	grid.add_child(_label("Offset pz"))
	var pz := _spin(pm.offset_pz, -100000.0, 100000.0, 0.01, " m")
	pz.tooltip_text = "Shift this block sideways (+ = left of travel)."
	pz.value_changed.connect(_on_spin.bind(pm, &"offset_pz", "Set block pz offset"))
	grid.add_child(pz)

	var hint := _label(_auto_text(pm))
	hint.modulate = Color(1, 1, 1, 0.6)
	_hints[pm] = hint
	v.add_child(hint)
	return margin


func _auto_text(pm: PathModule) -> String:
	if pm.scene == null:
		return "Choose a scene for this block."
	return "Auto length %.2f m (mesh extent minus overlap)" % _stitcher.measure_length(pm)


# ------------------------------------------------------------------------------
# Small control helpers
# ------------------------------------------------------------------------------


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	var theme := EditorInterface.get_editor_theme()
	if theme.has_font("bold", "EditorFonts"):
		l.add_theme_font_override("font", theme.get_font("bold", "EditorFonts"))
	if theme.has_color("accent_color", "Editor"):
		l.add_theme_color_override("font_color", theme.get_color("accent_color", "Editor"))
	return l


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _icon(icon_name: String) -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	if theme.has_icon(icon_name, "EditorIcons"):
		return theme.get_icon(icon_name, "EditorIcons")
	return null


func _spin(value: float, lo: float, hi: float, step: float, suffix := "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.allow_greater = true
	s.allow_lesser = lo < 0.0
	s.suffix = suffix
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _option(names: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.selected = selected
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return o


## A scene picker: Quick Load, Load, Clear, and drag a file onto it.
func _picker(scene: PackedScene, on_change: Callable) -> EditorResourcePicker:
	var p := EditorResourcePicker.new()
	p.base_type = "PackedScene"
	p.editable = true
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.edited_resource = scene
	p.resource_changed.connect(on_change)
	return p


func _expander(key: String) -> Button:
	var b := Button.new()
	b.flat = true
	var open: bool = _expanded.get(key, false)
	b.icon = _icon("GuiTreeArrowDown" if open else "GuiTreeArrowRight")
	if b.icon == null:
		b.text = "v" if open else ">"
	b.tooltip_text = "Length, overlap and offset for this block"
	b.pressed.connect(_toggle_expanded.bind(key))
	return b


# ------------------------------------------------------------------------------
# Edits (each is one undoable action)
# ------------------------------------------------------------------------------


func _apply(obj: Object, prop: StringName, value: Variant, label: String, merge := false) -> void:
	_ur.create_action(label, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE, _stitcher)
	_ur.add_do_property(obj, prop, value)
	_ur.add_undo_property(obj, prop, obj.get(prop))
	_own_edit = true
	_ur.commit_action()
	_own_edit = false


func _on_spin(value: float, obj: Object, prop: StringName, label: String) -> void:
	_apply(obj, prop, value, "%s %s %d" % [label, prop, obj.get_instance_id()], true)
	if obj is PathModule and _hints.has(obj):
		_hints[obj].text = _auto_text(obj)


func _on_int(value: float, obj: Object, prop: StringName, label: String) -> void:
	_apply(obj, prop, int(value), "%s %s %d" % [label, prop, obj.get_instance_id()], true)


func _create_sequence() -> void:
	_apply(_stitcher, &"sequence", PathSequence.new(), "Create building blocks")
	_queue_build()


func _on_end_scene(res: Resource, prop: StringName) -> void:
	var seq := _stitcher.sequence
	var pm: PathModule = seq.get(prop)
	if res == null:
		_apply(seq, prop, null, "Clear block")
	elif pm == null:
		var made := PathModule.new()
		made.scene = res as PackedScene
		_apply(seq, prop, made, "Set block")
	else:
		_apply(pm, &"scene", res, "Set block scene")
	_queue_build()


## A block-sequence or marker row's scene was changed (the row owns its module).
func _on_entry_scene(res: Resource, entry: Object) -> void:
	if entry.module == null:
		var made := PathModule.new()
		made.scene = res as PackedScene
		_apply(entry, &"module", made, "Set block")
	else:
		_apply(entry.module, &"scene", res, "Set block scene")
	_queue_build()


func _on_anchor(on: bool) -> void:
	_apply(_stitcher.sequence, &"anchor_end", on, "Anchor Last block to end of path")


func _on_randomize(on: bool) -> void:
	_apply(_stitcher.sequence, &"mode", PathSequence.Mode.RANDOM if on else PathSequence.Mode.PATTERN, "Toggle randomize")
	_queue_build()


func _on_fit(index: int) -> void:
	_apply(_stitcher.sequence, &"fit", index, "Set fit")


func _on_snap(index: int) -> void:
	_apply(_stitcher.sequence, &"marker_snap", index, "Set marker snap")


func _typed_pattern() -> Array[PathPatternEntry]:
	var arr: Array[PathPatternEntry] = []
	arr.assign(_stitcher.sequence.pattern)
	return arr


func _typed_markers() -> Array[PathMarkerEntry]:
	var arr: Array[PathMarkerEntry] = []
	arr.assign(_stitcher.sequence.markers)
	return arr


func _add_block() -> void:
	var entry := PathPatternEntry.new()
	entry.module = PathModule.new()
	var arr := _typed_pattern()
	arr.append(entry)
	_apply(_stitcher.sequence, &"pattern", arr, "Add block")
	_queue_build()


## Scene files dropped onto "Add block": one new row per scene, in one undo step.
func _add_blocks_from(scenes: Array) -> void:
	if scenes.is_empty():
		return
	var arr := _typed_pattern()
	for scene in scenes:
		var entry := PathPatternEntry.new()
		entry.module = PathModule.new()
		entry.module.scene = scene
		arr.append(entry)
	_apply(_stitcher.sequence, &"pattern", arr, "Add blocks" if scenes.size() > 1 else "Add block")
	_queue_build()


func _remove_block(index: int) -> void:
	var arr := _typed_pattern()
	arr.remove_at(index)
	_forget_block_expansion()
	_apply(_stitcher.sequence, &"pattern", arr, "Remove block")
	_queue_build()


func _move_block(from: int, to: int) -> void:
	if from == to:
		return
	var arr := _typed_pattern()
	var entry: PathPatternEntry = arr.pop_at(from)
	arr.insert(to, entry)
	_forget_block_expansion()
	_apply(_stitcher.sequence, &"pattern", arr, "Reorder blocks")
	_queue_build()


func _add_marker() -> void:
	var entry := PathMarkerEntry.new()
	entry.module = PathModule.new()
	var arr := _typed_markers()
	arr.append(entry)
	_apply(_stitcher.sequence, &"markers", arr, "Add marker")
	_queue_build()


func _remove_marker(index: int) -> void:
	var arr := _typed_markers()
	arr.remove_at(index)
	_apply(_stitcher.sequence, &"markers", arr, "Remove marker")
	_queue_build()


func _forget_block_expansion() -> void:
	for k in _expanded.keys():
		if String(k).begins_with("b"):
			_expanded.erase(k)


func _toggle_expanded(key: String) -> void:
	_expanded[key] = not _expanded.get(key, false)
	_queue_build()


# ------------------------------------------------------------------------------
# Refreshing after changes made elsewhere (undo, scripts)
# ------------------------------------------------------------------------------


func _watch(seq: PathSequence) -> void:
	if _watched == seq:
		return
	if _watched and _watched.changed.is_connected(_on_sequence_changed):
		_watched.changed.disconnect(_on_sequence_changed)
	_watched = seq
	if _watched:
		_watched.changed.connect(_on_sequence_changed)


func _on_sequence_changed() -> void:
	if not _own_edit:
		_queue_build()


func _on_history_changed() -> void:
	if not _own_edit:
		_queue_build()


func _queue_build() -> void:
	if _build_queued:
		return
	_build_queued = true
	_run_queued_build.call_deferred()


func _run_queued_build() -> void:
	_build_queued = false
	if is_instance_valid(_stitcher):
		_build()


# ------------------------------------------------------------------------------
# Drag and drop
# ------------------------------------------------------------------------------


## The grip at the left of a row. Drag it onto another row's grip to reorder.
class _Handle extends Label:
	var kind := ""
	var index := 0
	var on_drop: Callable

	func _init() -> void:
		text = "≡"
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		tooltip_text = "Drag onto another row's grip to reorder"

	func _get_drag_data(_at_position: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = "  %s %d  " % [kind, index + 1]
		set_drag_preview(preview)
		return {"path_stitcher_row": kind, "from": index}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("path_stitcher_row", "") == kind

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		on_drop.call(data.from, index)


## "Add block": a click adds an empty row; scene files dragged from the
## FileSystem dock and dropped on it are added as one row each.
class _DropButton extends Button:
	const SCENE_EXTENSIONS := ["blend", "glb", "gltf", "tscn", "scn"]
	var on_scenes: Callable

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return not _paths_from(data).is_empty()

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		var scenes := []
		for path in _paths_from(data):
			var res := ResourceLoader.load(path)
			if res is PackedScene:
				scenes.append(res)
		on_scenes.call(scenes)

	static func _paths_from(data: Variant) -> PackedStringArray:
		var out := PackedStringArray()
		if data is Dictionary and data.get("type", "") == "files":
			for f in data.get("files", []):
				if String(f).get_extension().to_lower() in SCENE_EXTENSIONS:
					out.append(f)
		return out
