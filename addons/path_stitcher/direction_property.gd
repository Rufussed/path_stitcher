@tool
extends EditorProperty
## An enum property shown as one toggle button per option (the choices come from
## the property's enum hint), used for PathSpiral's winding direction. Editing goes
## through the Inspector's normal property path, so undo and the live rebuild work.

var _buttons: Array[Button] = []
var _values: Array[int] = []
var _updating := false


## `options` are "Label:value" strings, as in an enum hint string.
func setup(options: PackedStringArray, tooltips: Array[String]) -> void:
	var row := HBoxContainer.new()
	var group := ButtonGroup.new()
	for i in options.size():
		var parts := options[i].split(":")
		var b := Button.new()
		b.text = parts[0]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i < tooltips.size():
			b.tooltip_text = tooltips[i]
		_values.append(int(parts[1]) if parts.size() > 1 else i)
		b.pressed.connect(_on_pressed.bind(i))
		row.add_child(b)
		add_focusable(b)
		_buttons.append(b)
	add_child(row)


func _update_property() -> void:
	var value: int = get_edited_object()[get_edited_property()]
	_updating = true
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(_values[i] == value)
	_updating = false


func _on_pressed(index: int) -> void:
	if not _updating:
		emit_changed(get_edited_property(), _values[index])
