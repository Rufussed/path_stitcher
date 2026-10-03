@tool
class_name PathMarkerEntry
extends Resource
## A module placed at a specific path distance, interrupting the sequence.
## (Markers can also be placed visually as PathMarker children of the Path3D.)

@export var module: PathModule:
	set(value):
		if module and module.changed.is_connected(emit_changed):
			module.changed.disconnect(emit_changed)
		module = value
		if module:
			module.changed.connect(emit_changed)
		emit_changed()

## Path distance (px) where the module's centre should land (m).
@export_range(0.0, 100000.0, 0.01, "or_greater", "suffix:m") var distance := 0.0:
	set(value):
		distance = maxf(value, 0.0)
		emit_changed()
