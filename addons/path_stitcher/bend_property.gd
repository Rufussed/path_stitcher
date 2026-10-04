@tool
extends EditorProperty
## PathStitcher's Bend setting as one dark panel: the label and two toggle buttons
## (Linear | Full, each with its own tooltip) on the first line, and under them
## the relative render cost of each mode, aligned under its button. The cost is
## draw calls + triangles / 10,000 for the current layout, shown as a percentage
## of the more expensive mode. Editing goes through the Inspector's normal
## property path, so undo and the live rebuild work as for any property.

# [label, tooltip, Bend value, key in PathStitcher.relative_costs()] in display order.
const CHOICES := [
	["Linear", "Full instancing - GPU optimized. Straight blocks with matched ends, for architecture.", 1, "linear"],
	["Full", "Full bend - follows the curve, for organic and sculpted forms.", 0, "full"],
]
const COST_TIP := "Draw calls + triangles / 10,000 for this path as laid out now, as if everything were in view,\nshown as a percentage of the more expensive mode. Lower is lighter. For comparing modes, not a frame time."

var _buttons: Array[Button] = []
var _cost_labels: Array[Label] = []
var _updating := false
var _connected: Object


func _init() -> void:
	set_draw_label(false) # the panel carries its own label

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	var rows := VBoxContainer.new()
	panel.add_child(rows)

	# Row 1: "Bend" on the left half, the two buttons on the right half.
	var top := HBoxContainer.new()
	var title := Label.new()
	title.text = "Bend"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var buttons := HBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var group := ButtonGroup.new()
	for i in CHOICES.size():
		var b := Button.new()
		b.text = CHOICES[i][0]
		b.tooltip_text = CHOICES[i][1]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_pressed.bind(i))
		buttons.add_child(b)
		add_focusable(b)
		_buttons.append(b)
	top.add_child(buttons)
	rows.add_child(top)

	# Row 2: a caption on the left half, one cost under each button on the right.
	var costs := HBoxContainer.new()
	var caption := Label.new()
	caption.text = "Relative render cost"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.modulate = Color(1, 1, 1, 0.6)
	caption.tooltip_text = COST_TIP
	caption.mouse_filter = Control.MOUSE_FILTER_STOP
	costs.add_child(caption)
	var values := HBoxContainer.new()
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in CHOICES.size():
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "-"
		l.tooltip_text = COST_TIP
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		values.add_child(l)
		_cost_labels.append(l)
	costs.add_child(values)
	rows.add_child(costs)

	add_child(panel)


func _ready() -> void:
	set_label("") # the Inspector sets the label after _init; the panel draws its own



func _panel_style() -> StyleBox:
	var theme := EditorInterface.get_editor_theme()
	var sb := StyleBoxFlat.new()
	sb.bg_color = theme.get_color("dark_color_2", "Editor") if theme.has_color("dark_color_2", "Editor") else Color(0.1, 0.1, 0.1)
	sb.set_corner_radius_all(int(3 * EditorInterface.get_editor_scale()))
	sb.set_content_margin_all(4.0 * EditorInterface.get_editor_scale())
	return sb


func _update_property() -> void:
	var obj := get_edited_object()
	var value: int = obj[get_edited_property()]
	_updating = true
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(CHOICES[i][2] == value)
	_updating = false
	if obj != _connected and obj.has_signal("rebuilt"):
		if _connected and _connected.rebuilt.is_connected(_refresh_costs):
			_connected.rebuilt.disconnect(_refresh_costs)
		_connected = obj
		obj.rebuilt.connect(_refresh_costs)
	_refresh_costs()


func _refresh_costs() -> void:
	var obj := get_edited_object()
	if obj == null or not obj.has_method("relative_costs"):
		return
	var costs: Dictionary = obj.relative_costs()
	# Shown as a percentage of the more expensive mode (that one reads 100%).
	var worst := 0
	for v in costs.values():
		worst = maxi(worst, v)
	for i in CHOICES.size():
		var key: String = CHOICES[i][3]
		_cost_labels[i].text = "%d%%" % roundi(100.0 * costs[key] / worst) if costs.has(key) and worst > 0 else "-"


func _exit_tree() -> void:
	if _connected and is_instance_valid(_connected) and _connected.rebuilt.is_connected(_refresh_costs):
		_connected.rebuilt.disconnect(_refresh_costs)


func _on_pressed(index: int) -> void:
	if not _updating:
		emit_changed(get_edited_property(), CHOICES[index][2])
