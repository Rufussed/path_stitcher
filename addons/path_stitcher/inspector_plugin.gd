@tool
extends EditorInspectorPlugin
## Replaces a PathStitcher's `sequence` property with the BUILDING BLOCKS editor,
## and its `bend` property with a two-button Full | Linear choice.

const BlocksEditor := preload("res://addons/path_stitcher/building_blocks_editor.gd")
const BendProperty := preload("res://addons/path_stitcher/bend_property.gd")


func _can_handle(object: Object) -> bool:
	return object is PathStitcher


func _parse_property(object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint,
		_hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name == "sequence":
		var editor := BlocksEditor.new()
		editor.setup(object)
		add_custom_control(editor)
		return true # hide the default resource slot
	if name == "bend":
		add_property_editor(name, BendProperty.new(), false, "Bend")
		return true # hide the default dropdown
	return false
