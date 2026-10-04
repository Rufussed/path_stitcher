@tool
extends EditorProperty
## PathStitcher's Bend setting as two toggle buttons on one line (Full | Linear),
## so each choice can carry its own tooltip. Editing goes through the Inspector's
## normal property path, so undo and the live rebuild work as for any property.

const CHOICES := [
	["Full", "Full bend - follows the curve, for organic and sculpted forms."],
	["Linear", "Full instancing - GPU optimized. Straight blocks with matched ends, for architecture."],
]

var _buttons: Array[Button] = []
var _updating := false


func _init() -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var group := ButtonGroup.new()
	for i in CHOICES.size():
		var b := Button.new()
		b.text = CHOICES[i][0]
		b.tooltip_text = CHOICES[i][1]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_pressed.bind(i))
		row.add_child(b)
		add_focusable(b)
		_buttons.append(b)
	add_child(row)


func _update_property() -> void:
	var value: int = get_edited_object()[get_edited_property()]
	_updating = true
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == value)
	_updating = false


func _on_pressed(index: int) -> void:
	if not _updating:
		emit_changed(get_edited_property(), index)
