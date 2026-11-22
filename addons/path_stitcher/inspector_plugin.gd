@tool
extends EditorInspectorPlugin
## Replaces a PathStitcher's `sections` property with the BUILDING BLOCKS editor,
## and its `bend` property with a two-button Full | Linear choice. A PathSpiral's
## `direction` is shown as an Anticlockwise | Clockwise button pair.

const BlocksEditor := preload("res://addons/path_stitcher/building_blocks_editor.gd")
const BendProperty := preload("res://addons/path_stitcher/bend_property.gd")
const DirectionProperty := preload("res://addons/path_stitcher/direction_property.gd")


func _can_handle(object: Object) -> bool:
	return object is PathStitcher or object is PathSpiral


func _parse_property(object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint,
		_hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name == "direction" and object is PathSpiral:
		var editor := DirectionProperty.new()
		editor.setup(PackedStringArray(["Anticlockwise:0", "Clockwise:1"]), [
			"Climb anticlockwise seen from above, like classic Tower of Babel pictures. The outside of the turn is the path's right.",
			"Climb clockwise seen from above. The outside of the turn is the path's left, so turn on the PathStitcher's Flip Side to keep blocks facing outwards.",
		])
		add_property_editor(name, editor, false, "Direction")
		return true
	if name == "markers" or name == "marker_snap":
		return true # shown inside the BUILDING BLOCKS editor
	if name == "sections":
		var editor := BlocksEditor.new()
		editor.setup(object)
		add_custom_control(editor)
		return true # hide the default resource slot
	if name == "bend":
		add_property_editor(name, BendProperty.new(), false, "Bend")
		return true # hide the default dropdown
	return false
