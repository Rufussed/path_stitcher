@tool
class_name PathMarker
extends Marker3D
## A visual marker: place it as a child of a Path3D and choose its module. In
## the editor it snaps onto the path as you move it, and any PathStitcher
## on that path puts the module's centre here.

## The block placed at this marker's spot on the path.
@export var module: PathModule:
	set(value):
		module = value
		update_gizmos()

var _snapping := false


func _ready() -> void:
	set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint() and not _snapping:
		var p := get_parent() as Path3D
		if p and p.curve and p.curve.point_count > 1:
			var on_path := p.curve.get_closest_point(position)
			if not on_path.is_equal_approx(position):
				_snapping = true
				position = on_path
				_snapping = false


## This marker's distance along its parent path (m), or -1 if not on a path.
func path_distance() -> float:
	var p := get_parent() as Path3D
	if p == null or p.curve == null:
		return -1.0
	return p.curve.get_closest_offset(position)
