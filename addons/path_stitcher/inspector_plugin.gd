@tool
extends EditorInspectorPlugin
## Replaces a PathStitcher's `sequence` property with the BUILDING BLOCKS editor.

const BlocksEditor := preload("res://addons/path_stitcher/building_blocks_editor.gd")


func _can_handle(object: Object) -> bool:
	return object is PathStitcher


func _parse_property(object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint,
		_hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name == "sequence":
		var editor := BlocksEditor.new()
		editor.setup(object)
		add_custom_control(editor)
		return true # hide the default resource slot
	return false
