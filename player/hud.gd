extends CanvasLayer
## Top-centred HUD: path-following arrow and actual movement speed in m/s.
## The arrow is white while following a path, grey while free roaming.

@export var player_path := NodePath("../Player")
## Arrow height in pixels.
@export var size := 36.0
## Distance from the top edge of the screen in pixels.
@export var top_margin := 28.0
@export var speed_font_size := 24
@export var speed_gap := 12.0

const COLOR_ON := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_OFF := Color(0.5, 0.5, 0.5, 0.75)
const SPEED_WIDTH := 150.0

var _player: CharacterBody3D
var _arrow: Control
var _speed_label: Label
var _shown := false


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_arrow = Control.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
	_speed_label = Label.new()
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_label.text = "0.0 km/h"
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_label.add_theme_font_size_override("font_size", speed_font_size)
	_speed_label.add_theme_color_override("font_color", COLOR_ON)
	_speed_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_speed_label.add_theme_constant_override("shadow_offset_x", 1)
	_speed_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_speed_label)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var on: bool = _player.get(&"path_following") == true
	if on != _shown or _arrow.size == Vector2.ZERO:
		_shown = on
		_arrow.queue_redraw()
	# Convert world velocity to metres relative to the current player size.
	# Use the same scale and minimum as the player movement code.
	var player_scale := maxf(GameParams.get_active().player_scale, 0.01)
	_speed_label.text = "%.1f km/h" % (_player.get_real_velocity().length() / player_scale * 3.6)
	# Keep a fixed-width group centred so changing digits do not move the arrow.
	var view := get_viewport().get_visible_rect().size
	var group_width := size + speed_gap + SPEED_WIDTH
	var left := (view.x - group_width) * 0.5
	var row_height := maxf(size, _speed_label.get_minimum_size().y)
	_arrow.size = Vector2(size, size)
	_arrow.position = Vector2(left, top_margin + (row_height - size) * 0.5)
	_speed_label.size = Vector2(SPEED_WIDTH, row_height)
	_speed_label.position = Vector2(left + size + speed_gap, top_margin)


## An up-pointing arrow: a triangle head over a short stem.
func _draw_arrow() -> void:
	var c := COLOR_ON if _shown else COLOR_OFF
	var w := size * 0.5
	var head := PackedVector2Array([Vector2(w, 0.0), Vector2(size, size * 0.5), Vector2(0.0, size * 0.5)])
	_arrow.draw_colored_polygon(head, c)
	_arrow.draw_rect(Rect2(w - size * 0.14, size * 0.5, size * 0.28, size * 0.5), c)
