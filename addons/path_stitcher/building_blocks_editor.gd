@tool
extends VBoxContainer
## The BUILDING BLOCKS section of a PathStitcher's Inspector: one box per section
## (a name and length on top, then the section's own blocks, below), an
## "Add section" button, and a MARKERS box. Each section's box holds:
##   a "First" row at the top, the reorderable block rows (drag the grip), an
##   always-present empty slot at the end of the list (pick or drop scene files
##   into it and it becomes a block, with a new empty slot below), a "Last" row
##   with an "Anchor Last block to end of path" toggle, the fit mode, and
##   Randomize (with seed and max repeat). Every row has a multiplier: a repeat
##   count (a weight for the middle rows when Randomize is on) and an expander
##   for that block's length (px), overlap and offset (vert, horz).
## The MARKERS box holds blocks at fixed path distances, across all sections.
## Every edit is one undoable editor action.

const ScenePicker := preload("res://addons/path_stitcher/scene_picker.gd")

const FIT_NAMES := ["Stretch", "Truncate pattern", "Finish cycle", "None"]
const SNAP_NAMES := ["Exact", "Nearest joint"]
# Fixed widths, in editor-scale-1 pixels (scaled by _px so they hold on HiDPI).
# HANDLE_WIDTH must be wider than the words "First" / "Last" so that every row's
# scene box starts at the same position.
const HANDLE_WIDTH := 48 # the grip / "First" / "Last" column
const BUTTON_WIDTH := 34 # expander and remove columns (the icon buttons' own width)
const COUNT_WIDTH := 40
const DISTANCE_WIDTH := 55

var _stitcher: PathStitcher
var _ur: EditorUndoRedoManager
var _watched: Array[PathSection] = []
var _expanded := {}
var _hints := {}
var _build_queued := false
var _own_edit := false


func setup(stitcher: Object) -> void:
	_stitcher = stitcher as PathStitcher
	_ur = EditorInterface.get_editor_undo_redo()
	_ur.version_changed.connect(_on_history_changed)
	add_theme_constant_override("separation", int(_px(4)))
	_build()


func _exit_tree() -> void:
	if _ur and _ur.version_changed.is_connected(_on_history_changed):
		_ur.version_changed.disconnect(_on_history_changed)
	_watch([])


## A fixed size scaled for the editor's display scale.
func _px(v: float) -> float:
	return v * EditorInterface.get_editor_scale()


# ------------------------------------------------------------------------------
# Building the controls
# ------------------------------------------------------------------------------


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_hints.clear()
	_watch(_stitcher.sections)

	if _stitcher.sections.is_empty():
		var empty := VBoxContainer.new()
		empty.add_child(_header("BUILDING BLOCKS"))
		empty.add_child(_add_section_button())
		add_child(_boxed(empty))
		return
	for i in _stitcher.sections.size():
		if _stitcher.sections[i] != null:
			add_child(_boxed(_section_box(i)))
	add_child(_add_section_button())
	add_child(_boxed(_markers_section()))


func _add_section_button() -> Button:
	var add := Button.new()
	add.text = "Add section"
	add.icon = _icon("Add")
	add.tooltip_text = "Add a section: a stretch of the path with its own start block, repeating pattern and end block. Sections are laid end to end."
	add.pressed.connect(_add_section)
	return add


func _section_box(si: int) -> Control:
	var seq: PathSection = _stitcher.sections[si]
	var random := seq.mode == PathSection.Mode.RANDOM
	var box := VBoxContainer.new()

	# Header: name, length, and the section's own buttons.
	var head := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.text = seq.title
	name_edit.placeholder_text = "Section %d" % (si + 1)
	name_edit.tooltip_text = "A name for this section (optional)."
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.size_flags_stretch_ratio = 2.0
	name_edit.custom_minimum_size.x = _px(90)
	name_edit.text_submitted.connect(_on_title.bind(seq))
	name_edit.focus_exited.connect(func(): _on_title(name_edit.text, seq))
	head.add_child(name_edit)
	var len_spin := _spin(seq.length, 0.0, 100000.0, 0.1, " m")
	len_spin.tooltip_text = "How far along the path this section runs. 0 = share whatever the other sections leave over."
	len_spin.custom_minimum_size.x = _px(90)
	len_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	len_spin.size_flags_stretch_ratio = 1.5
	len_spin.value_changed.connect(_on_spin.bind(seq, &"length", "Set section length"))
	head.add_child(len_spin)
	head.add_child(_icon_button("MoveUp", "^", "Move this section earlier along the path", _move_section.bind(si, -1), si > 0))
	head.add_child(_icon_button("MoveDown", "v", "Move this section later along the path", _move_section.bind(si, 1), si < _stitcher.sections.size() - 1))
	head.add_child(_icon_button("Remove", "x", "Remove this section", _remove_section.bind(si), true))
	box.add_child(head)

	box.add_child(_end_row(seq, si, "First", &"start", &"start_count"))

	# A label for the middle part, like First and Last have.
	var mid := HBoxContainer.new()
	var mid_label := _label("Repeat")
	mid_label.custom_minimum_size.x = _px(HANDLE_WIDTH)
	mid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid_label.tooltip_text = ("The blocks between First and Last, drawn at random; each row's number is its weight."
			if random else "The blocks between First and Last, repeated in this order to fill the section.")
	mid_label.mouse_filter = Control.MOUSE_FILTER_STOP
	mid.add_child(mid_label)
	var rnd := CheckBox.new()
	rnd.text = "Randomize"
	rnd.tooltip_text = "Off: the blocks repeat in this order, each row repeated by its count.\nOn: blocks are drawn at random to fill the section, for mixed buildings along a street; each row's number is its weight."
	rnd.button_pressed = random
	rnd.toggled.connect(_on_randomize.bind(seq))
	mid.add_child(rnd)
	var mid_rule := HSeparator.new()
	mid_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(mid_rule)
	box.add_child(mid)
	for i in seq.pattern.size():
		box.add_child(_block_row(seq, si, i, random))
	box.add_child(_empty_slot_row(seq, random))
	box.add_child(_end_row(seq, si, "Last", &"end", &"end_count"))

	var fit_row := HBoxContainer.new()
	fit_row.add_child(_column_label("Fit"))
	var fit := _option(FIT_NAMES, seq.fit)
	fit.tooltip_text = "How the blocks are made to fill the section exactly.\nStretch: whole blocks, all stretched slightly.\nTruncate pattern: as many whole blocks as fit, then stretched.\nFinish cycle: whole cycles of the sequence only.\nNone: no stretching; a gap may remain."
	fit.item_selected.connect(_on_fit.bind(seq))
	fit_row.add_child(fit)
	box.add_child(fit_row)

	if random:
		var r := HBoxContainer.new()
		r.add_child(_column_label("Seed"))
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


## The First / Last row: a label in the grip column, the scene picker, the
## multiplier, and the expander. The Last row also carries the anchor toggle on
## its own line underneath.
func _end_row(seq: PathSection, si: int, title: String, prop: StringName, count_prop: StringName) -> Control:
	var pm: PathModule = seq.get(prop)
	var first := prop == &"start"
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	box.add_child(row)

	row.add_child(_column_label(title))
	row.add_child(_picker(pm.scene if pm else null, _on_end_scene.bind(prop, seq)))
	row.add_child(_count_spin(seq.get(count_prop), "×",
			"How many copies of the %s block sit at the %s of the path." % ["first" if first else "last", "start" if first else "end"],
			seq, count_prop, "Set %s block count" % ("first" if first else "last")))
	if pm:
		row.add_child(_expander("s%d_%s" % [si, prop]))
	else:
		row.add_child(_spacer(BUTTON_WIDTH))
	if pm:
		var del := Button.new()
		del.flat = true
		del.icon = _icon("Remove")
		if del.icon == null:
			del.text = "x"
		del.custom_minimum_size.x = _px(BUTTON_WIDTH)
		del.tooltip_text = "Remove the %s block" % ("first" if first else "last")
		del.pressed.connect(_clear_end.bind(prop, seq))
		row.add_child(del)
	else:
		row.add_child(_spacer(BUTTON_WIDTH))

	if not first:
		var anchor_row := HBoxContainer.new()
		anchor_row.add_child(_spacer(HANDLE_WIDTH))
		var anchor := CheckBox.new()
		anchor.text = "Anchor Last block to end of path"
		anchor.tooltip_text = "Place the Last block exactly at the end of the path, unstretched.\nOnly the blocks before it are fitted."
		anchor.button_pressed = seq.anchor_end
		anchor.toggled.connect(_on_anchor.bind(seq))
		anchor_row.add_child(anchor)
		box.add_child(anchor_row)
	if pm and _expanded.get("s%d_%s" % [si, prop], false):
		box.add_child(_detail(pm))
	return box


func _block_row(seq: PathSection, si: int, i: int, random: bool) -> Control:
	var entry: PathPatternEntry = seq.pattern[i]
	var v := VBoxContainer.new()
	var row := HBoxContainer.new()
	v.add_child(row)

	var handle := _Handle.new()
	handle.kind = "block%d" % si
	handle.index = i
	handle.on_drop = _move_block.bind(seq)
	handle.custom_minimum_size.x = _px(HANDLE_WIDTH)
	row.add_child(handle)
	row.add_child(_picker(entry.module.scene if entry.module else null, _on_entry_scene.bind(entry)))
	row.add_child(_count_spin(entry.count, "wt " if random else "×",
			"Weight: how often this block is picked." if random else "How many of this block in a row.",
			entry, &"count", "Set block count"))
	row.add_child(_expander("s%d_b%d" % [si, i]))
	var del := Button.new()
	del.flat = true
	del.icon = _icon("Remove")
	if del.icon == null:
		del.text = "x"
	del.custom_minimum_size.x = _px(BUTTON_WIDTH)
	del.tooltip_text = "Remove this block"
	del.pressed.connect(_remove_block.bind(i, seq))
	row.add_child(del)

	if entry.module and _expanded.get("s%d_b%d" % [si, i], false):
		v.add_child(_detail(entry.module))
	return v


## The empty slot at the end of the block list. Choosing a scene in it (or
## dropping scene files on it) adds real block rows and a fresh empty slot
## appears below them.
func _empty_slot_row(seq: PathSection, random: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_spacer(HANDLE_WIDTH))
	var slot := ScenePicker.new()
	slot.accept_multiple = true
	slot.scene_changed.connect(_on_slot_scene.bind(seq))
	slot.scenes_dropped.connect(_add_blocks_from.bind(seq))
	row.add_child(slot)
	# A faded, disabled multiplier keeps the columns lined up with the rows above.
	var count := _spin(1, 1.0, 1000.0, 1.0)
	count.prefix = "wt " if random else "×"
	count.custom_minimum_size.x = _px(COUNT_WIDTH)
	count.size_flags_horizontal = Control.SIZE_SHRINK_END
	count.editable = false
	count.modulate = Color(1, 1, 1, 0.4)
	row.add_child(count)
	row.add_child(_spacer(BUTTON_WIDTH))
	row.add_child(_spacer(BUTTON_WIDTH))
	return row


func _markers_section() -> Control:
	var box := VBoxContainer.new()
	var head := _header("MARKERS")
	head.tooltip_text = "Place a specific block at a chosen spot on the path (a gate, a door, a bridge) instead of leaving it to the repeating pattern."
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(head)
	for i in _stitcher.markers.size():
		var entry: PathMarkerEntry = _stitcher.markers[i]
		var row := HBoxContainer.new()
		row.add_child(_picker(entry.module.scene if entry.module else null, _on_entry_scene.bind(entry)))
		row.add_child(_label("at"))
		var dist := _spin(entry.distance, 0.0, 1000000.0, 0.1, " m")
		dist.tooltip_text = "Path distance (m) where the block's centre lands."
		dist.custom_minimum_size.x = _px(DISTANCE_WIDTH)
		dist.size_flags_horizontal = Control.SIZE_SHRINK_END
		dist.value_changed.connect(_on_spin.bind(entry, &"distance", "Set marker distance"))
		row.add_child(dist)
		var del := Button.new()
		del.flat = true
		del.icon = _icon("Remove")
		if del.icon == null:
			del.text = "x"
		del.custom_minimum_size.x = _px(BUTTON_WIDTH)
		del.tooltip_text = "Remove this marker"
		del.pressed.connect(_remove_marker.bind(i))
		row.add_child(del)
		box.add_child(row)

	var buttons := HBoxContainer.new()
	var add := Button.new()
	add.text = "Add marker"
	add.icon = _icon("Add")
	add.tooltip_text = "Place a specific block at a chosen spot on the path (a gate, a door, a bridge) instead of leaving it to the repeating pattern."
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
	snap_row.add_child(_column_label("Snap"))
	var snap := _option(SNAP_NAMES, _stitcher.marker_snap)
	snap.tooltip_text = "Exact: the marker sits at its distance and the blocks around it are fitted.\nNearest joint: the marker replaces the closest block in its section."
	snap.item_selected.connect(_on_snap)
	snap_row.add_child(snap)
	box.add_child(snap_row)
	return box


## Length / overlap / offset controls for one block.
func _detail(pm: PathModule) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(_px(HANDLE_WIDTH)))
	var v := VBoxContainer.new()
	margin.add_child(v)
	var grid := GridContainer.new()
	grid.columns = 4
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
	# One "Offset" row with px (along the path), py (up) and pz (sideways, + = left).
	var off_row := HBoxContainer.new()
	var off_label := _label("Offset")
	off_label.tooltip_text = "Move this block relative to its place on the path."
	off_row.add_child(off_label)
	var px := _spin(pm.offset_px, -100000.0, 100000.0, 0.01)
	px.prefix = "px "
	px.tooltip_text = "Slide this block along the path (px). The spacing of its neighbours is unchanged."
	px.value_changed.connect(_on_spin.bind(pm, &"offset_px", "Set block px offset"))
	off_row.add_child(px)
	var py := _spin(pm.offset_py, -100000.0, 100000.0, 0.01)
	py.prefix = "py "
	py.tooltip_text = "Raise or lower this block (py)."
	py.value_changed.connect(_on_spin.bind(pm, &"offset_py", "Set block py offset"))
	off_row.add_child(py)
	var pz := _spin(pm.offset_pz, -100000.0, 100000.0, 0.01)
	pz.prefix = "pz "
	pz.tooltip_text = "Shift this block sideways (pz; + = left of travel)."
	pz.value_changed.connect(_on_spin.bind(pm, &"offset_pz", "Set block pz offset"))
	off_row.add_child(pz)
	v.add_child(off_row)

	var fit_row := HBoxContainer.new()
	fit_row.add_child(_label("Along px"))
	var fit_opt := _option(["Place", "Stretch"], 1 if pm.stretch_to_length else 0)
	fit_opt.tooltip_text = "What Length does to the block along the path.\nPlace: the block keeps its size and is placed every Length (a longer Length leaves gaps).\nStretch: the block is stretched along the path to fill Length."
	fit_opt.item_selected.connect(_on_length_fit.bind(pm))
	fit_row.add_child(fit_opt)
	v.add_child(fit_row)


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


## Wraps a section in the editor's standard sub-inspector box (background and
## outline), so each section reads as one group.
func _boxed(content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box_style())
	panel.add_child(content)
	return panel


func _box_style() -> StyleBox:
	var theme := EditorInterface.get_editor_theme()
	var sb: StyleBox
	if theme.has_stylebox("sub_inspector_bg0", "Editor"):
		sb = theme.get_stylebox("sub_inspector_bg0", "Editor").duplicate()
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0, 0, 0, 0.15)
		flat.set_border_width_all(1)
		flat.border_color = theme.get_color("accent_color", "Editor") if theme.has_color("accent_color", "Editor") else Color(0.5, 0.6, 0.8)
		flat.set_corner_radius_all(4)
		sb = flat
	sb.set_content_margin_all(_px(4))
	return sb


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


## A label in the left-hand column ("First", "Last", "Fit", the grips): the same
## width on every row so the pickers line up.
func _column_label(text: String) -> Label:
	var l := _label(text)
	l.custom_minimum_size.x = _px(HANDLE_WIDTH)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _spacer(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = _px(width)
	return c


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


## The multiplier box at the right of a row.
func _count_spin(value: int, prefix: String, tip: String, obj: Object, prop: StringName, label: String) -> SpinBox:
	var s := _spin(value, 1.0, 1000.0, 1.0)
	s.prefix = prefix
	s.custom_minimum_size.x = _px(COUNT_WIDTH)
	s.size_flags_horizontal = Control.SIZE_SHRINK_END
	s.tooltip_text = tip
	s.value_changed.connect(_on_int.bind(obj, prop, label))
	return s


func _option(names: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for n in names:
		o.add_item(n)
	o.selected = selected
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return o


## A compact scene picker (file name + dropdown), one line high.
func _picker(scene: PackedScene, on_change: Callable) -> Control:
	var p := ScenePicker.new()
	p.set_scene(scene)
	p.scene_changed.connect(on_change)
	return p


func _icon_button(icon_name: String, fallback: String, tip: String, on_press: Callable, enabled: bool) -> Button:
	var b := Button.new()
	b.flat = true
	b.icon = _icon(icon_name)
	if b.icon == null:
		b.text = fallback
	b.custom_minimum_size.x = _px(BUTTON_WIDTH)
	b.tooltip_text = tip
	b.disabled = not enabled
	b.pressed.connect(on_press)
	return b


func _expander(key: String) -> Button:
	var b := Button.new()
	b.flat = true
	var open: bool = _expanded.get(key, false)
	b.icon = _icon("GuiTreeArrowDown" if open else "GuiTreeArrowRight")
	if b.icon == null:
		b.text = "v" if open else ">"
	b.custom_minimum_size.x = _px(BUTTON_WIDTH)
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


func _on_length_fit(index: int, pm: PathModule) -> void:
	_apply(pm, &"stretch_to_length", index == 1, "Set length fit %d" % pm.get_instance_id())



func _add_section() -> void:
	var arr := _typed_sections()
	var sec := PathSection.new()
	arr.append(sec)
	_apply(_stitcher, &"sections", arr, "Add section")
	_queue_build()


func _remove_section(index: int) -> void:
	var arr := _typed_sections()
	arr.remove_at(index)
	_expanded.clear()
	_apply(_stitcher, &"sections", arr, "Remove section")
	_queue_build()


func _move_section(index: int, delta: int) -> void:
	var to := index + delta
	var arr := _typed_sections()
	if to < 0 or to >= arr.size():
		return
	var sec: PathSection = arr.pop_at(index)
	arr.insert(to, sec)
	_expanded.clear()
	_apply(_stitcher, &"sections", arr, "Move section")
	_queue_build()


func _on_title(text: String, seq: PathSection) -> void:
	if text != seq.title:
		_apply(seq, &"title", text, "Name section")


## The trash button on a First / Last row: empties that slot (the count is kept).
func _clear_end(prop: StringName, seq: PathSection) -> void:
	_apply(seq, prop, null, "Clear %s block" % ("first" if prop == &"start" else "last"))
	_queue_build()


func _on_end_scene(res: Resource, prop: StringName, seq: PathSection) -> void:
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


## A scene was chosen in the empty slot: it becomes a block row.
func _on_slot_scene(scene: PackedScene, seq: PathSection) -> void:
	if scene:
		_add_blocks_from([scene], seq)


func _on_anchor(on: bool, seq: PathSection) -> void:
	_apply(seq, &"anchor_end", on, "Anchor Last block to end of path")


func _on_randomize(on: bool, seq: PathSection) -> void:
	_apply(seq, &"mode", PathSection.Mode.RANDOM if on else PathSection.Mode.PATTERN, "Toggle randomize")
	_queue_build()


func _on_fit(index: int, seq: PathSection) -> void:
	_apply(seq, &"fit", index, "Set fit")


func _on_snap(index: int) -> void:
	_apply(_stitcher, &"marker_snap", index, "Set marker snap")


func _typed_sections() -> Array[PathSection]:
	var arr: Array[PathSection] = []
	arr.assign(_stitcher.sections)
	return arr


func _typed_pattern(seq: PathSection) -> Array[PathPatternEntry]:
	var arr: Array[PathPatternEntry] = []
	arr.assign(seq.pattern)
	return arr


func _typed_markers() -> Array[PathMarkerEntry]:
	var arr: Array[PathMarkerEntry] = []
	arr.assign(_stitcher.markers)
	return arr


## Scenes chosen in or dropped on the empty slot: one new block row per scene,
## in one undo step.
func _add_blocks_from(scenes: Array, seq: PathSection) -> void:
	if scenes.is_empty():
		return
	var arr := _typed_pattern(seq)
	for scene in scenes:
		var entry := PathPatternEntry.new()
		entry.module = PathModule.new()
		entry.module.scene = scene
		arr.append(entry)
	_apply(seq, &"pattern", arr, "Add blocks" if scenes.size() > 1 else "Add block")
	_queue_build()


func _remove_block(index: int, seq: PathSection) -> void:
	var arr := _typed_pattern(seq)
	arr.remove_at(index)
	_forget_block_expansion()
	_apply(seq, &"pattern", arr, "Remove block")
	_queue_build()


func _move_block(from: int, to: int, seq: PathSection) -> void:
	if from == to:
		return
	var arr := _typed_pattern(seq)
	var entry: PathPatternEntry = arr.pop_at(from)
	arr.insert(to, entry)
	_forget_block_expansion()
	_apply(seq, &"pattern", arr, "Reorder blocks")
	_queue_build()


func _add_marker() -> void:
	var entry := PathMarkerEntry.new()
	entry.module = PathModule.new()
	var arr := _typed_markers()
	arr.append(entry)
	_apply(_stitcher, &"markers", arr, "Add marker")
	_queue_build()


func _remove_marker(index: int) -> void:
	var arr := _typed_markers()
	arr.remove_at(index)
	_apply(_stitcher, &"markers", arr, "Remove marker")
	_queue_build()


func _forget_block_expansion() -> void:
	for k in _expanded.keys():
		if "_b" in String(k):
			_expanded.erase(k)


func _toggle_expanded(key: String) -> void:
	_expanded[key] = not _expanded.get(key, false)
	_queue_build()


# ------------------------------------------------------------------------------
# Refreshing after changes made elsewhere (undo, scripts)
# ------------------------------------------------------------------------------


func _watch(secs: Array) -> void:
	for w in _watched:
		if is_instance_valid(w) and w.changed.is_connected(_on_sequence_changed):
			w.changed.disconnect(_on_sequence_changed)
	_watched.clear()
	for sec in secs:
		if sec is PathSection:
			sec.changed.connect(_on_sequence_changed)
			_watched.append(sec)


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
