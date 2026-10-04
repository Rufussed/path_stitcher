extends CanvasLayer
## Heads-up display. A small forward arrow at the bottom centre of the screen
## shows whether the player is following a path: white when on, grey when off
## (free roaming). Left Shift toggles it; it switches itself off when the
## player is too far from every path or has several in range.

@export var player_path := NodePath("../Player")
## Arrow height in pixels.
@export var size := 36.0
## Distance from the bottom edge of the screen in pixels; the arrow is centred
## horizontally and follows the window size.
@export var bottom_margin := 28.0

const COLOR_ON := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_OFF := Color(0.5, 0.5, 0.5, 0.75)

var _player: Node
var _arrow: Control
var _shown := false


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_arrow = Control.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)


func _process(_delta: float) -> void:
	if _player == null:
		return
	var on: bool = _player.get(&"path_following") == true
	if on != _shown or _arrow.size == Vector2.ZERO:
		_shown = on
		_arrow.queue_redraw()
	# Positioned from the bottom centre, so it stays put when the window resizes.
	var view := get_viewport().get_visible_rect().size
	_arrow.size = Vector2(size, size)
	_arrow.position = Vector2(view.x * 0.5 - size * 0.5, view.y - bottom_margin - size)


## An up-pointing arrow: a triangle head over a short stem.
func _draw_arrow() -> void:
	var c := COLOR_ON if _shown else COLOR_OFF
	var w := size * 0.5
	var head := PackedVector2Array([Vector2(w, 0.0), Vector2(size, size * 0.5), Vector2(0.0, size * 0.5)])
	_arrow.draw_colored_polygon(head, c)
	_arrow.draw_rect(Rect2(w - size * 0.14, size * 0.5, size * 0.28, size * 0.5), c)
