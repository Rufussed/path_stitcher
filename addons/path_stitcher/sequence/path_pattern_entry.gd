@tool
class_name PathPatternEntry
extends Resource
## One row of a PathSequence's block sequence. In pattern mode: `count` copies
## of `module` in a row. In random mode: `count` is the block's weight.

@export var module: PathModule:
	set(value):
		if module and module.changed.is_connected(emit_changed):
			module.changed.disconnect(emit_changed)
		module = value
		if module:
			module.changed.connect(emit_changed)
		emit_changed()

@export_range(1, 1000, 1, "or_greater") var count := 1:
	set(value):
		count = maxi(value, 1)
		emit_changed()
