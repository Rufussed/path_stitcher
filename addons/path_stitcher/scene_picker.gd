@tool
extends HBoxContainer
## A compact scene picker for the PathStitcher Inspector: one button showing the
## scene's file name (click = Quick Load) and a dropdown with Quick Load, Load,
## Clear and Show in FileSystem. Scene files dragged from the FileSystem dock
## and dropped on it are accepted. Unlike Godot's EditorResourcePicker it never
## grows a large thumbnail, so rows stay one line high.

## Emitted when the user picks or clears a scene (null = cleared).
signal scene_changed(scene: PackedScene)
## Emitted instead when several scene files are dropped at once and
## `accept_multiple` is on.
signal scenes_dropped(scenes: Array)

const EXTENSIONS := ["blend", "glb", "gltf", "tscn", "scn"]
enum Item { QUICK_LOAD, LOAD, CLEAR, SHOW }

## Treat a drop of several scene files as "scenes_dropped" rather than keeping
## only the first.
var accept_multiple := false

var _scene: PackedScene
var _button := Button.new()
var _menu := MenuButton.new()
var _dialog: EditorFileDialog


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 2)

	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.clip_text = true
	_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_button.pressed.connect(_quick_load)
	_button.set_drag_forwarding(Callable(), _can_drop, _drop)
	add_child(_button)

	var theme := EditorInterface.get_editor_theme()
	if theme.has_icon("GuiOptionArrow", "EditorIcons"):
		_menu.icon = theme.get_icon("GuiOptionArrow", "EditorIcons")
	else:
		_menu.text = "v"
	var popup := _menu.get_popup()
	popup.add_item("Quick Load…", Item.QUICK_LOAD)
	popup.add_item("Load…", Item.LOAD)
	popup.add_separator()
	popup.add_item("Clear", Item.CLEAR)
	popup.add_item("Show in FileSystem", Item.SHOW)
	popup.id_pressed.connect(_on_menu)
	add_child(_menu)
	_refresh()


## Shows `scene` without emitting `scene_changed`.
func set_scene(scene: PackedScene) -> void:
	_scene = scene
	_refresh()


func _refresh() -> void:
	var theme := EditorInterface.get_editor_theme()
	if _scene:
		_button.text = _scene.resource_path.get_file()
		_button.tooltip_text = _scene.resource_path
		_button.modulate = Color.WHITE
	else:
		_button.text = "<empty>"
		_button.tooltip_text = "Click to choose a scene (.blend, .glb, .gltf, .tscn), or drag scene files from the FileSystem dock onto this."
		_button.modulate = Color(1, 1, 1, 0.6)
	if theme.has_icon("PackedScene", "EditorIcons"):
		_button.icon = theme.get_icon("PackedScene", "EditorIcons")
	var popup := _menu.get_popup()
	popup.set_item_disabled(popup.get_item_index(Item.CLEAR), _scene == null)
	popup.set_item_disabled(popup.get_item_index(Item.SHOW), _scene == null)


func _quick_load() -> void:
	EditorInterface.popup_quick_open(_on_path_picked, [&"PackedScene"])


func _on_menu(id: int) -> void:
	match id:
		Item.QUICK_LOAD:
			_quick_load()
		Item.LOAD:
			if _dialog == null:
				_dialog = EditorFileDialog.new()
				_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
				_dialog.access = EditorFileDialog.ACCESS_RESOURCES
				_dialog.add_filter("*.blend, *.glb, *.gltf, *.tscn, *.scn", "Scenes")
				_dialog.file_selected.connect(_on_path_picked)
				add_child(_dialog)
			_dialog.popup_file_dialog()
		Item.CLEAR:
			_scene = null
			_refresh()
			scene_changed.emit(null)
		Item.SHOW:
			if _scene:
				EditorInterface.get_file_system_dock().navigate_to_path(_scene.resource_path)


func _on_path_picked(path: String) -> void:
	if path.is_empty():
		return
	var res := ResourceLoader.load(path)
	if res is PackedScene:
		_scene = res
		_refresh()
		scene_changed.emit(res)


func _dropped_paths(data: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if data is Dictionary and data.get("type", "") == "files":
		for f in data.get("files", []):
			if String(f).get_extension().to_lower() in EXTENSIONS:
				out.append(f)
	return out


func _can_drop(_at_position: Vector2, data: Variant) -> bool:
	return not _dropped_paths(data).is_empty()


func _drop(_at_position: Vector2, data: Variant) -> void:
	var paths := _dropped_paths(data)
	if accept_multiple and paths.size() > 1:
		var scenes := []
		for p in paths:
			var res := ResourceLoader.load(p)
			if res is PackedScene:
				scenes.append(res)
		scenes_dropped.emit(scenes)
	elif not paths.is_empty():
		_on_path_picked(paths[0])
