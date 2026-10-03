@tool
extends EditorPlugin
## Registers the inspector plugin that draws the BUILDING BLOCKS section of a
## PathStitcher node.

const InspectorPlugin := preload("res://addons/path_stitcher/inspector_plugin.gd")

var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	_inspector = InspectorPlugin.new()
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	if _inspector:
		remove_inspector_plugin(_inspector)
		_inspector = null
