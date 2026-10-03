@tool
class_name PathRandomEntry
extends Resource
## One choice in a random PathSequence: `module` is picked with probability
## proportional to `weight`.

@export var module: PathModule:
	set(value):
		if module and module.changed.is_connected(emit_changed):
			module.changed.disconnect(emit_changed)
		module = value
		if module:
			module.changed.connect(emit_changed)
		emit_changed()

@export_range(0.0, 100.0, 0.01, "or_greater") var weight := 1.0:
	set(value):
		weight = maxf(value, 0.0)
		emit_changed()
