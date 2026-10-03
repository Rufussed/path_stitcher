@tool
class_name PathSequence
extends Resource
## What a PathStitcher places along its path: an optional start module, a
## repeating pattern (or a seeded random draw), an optional end module, and
## markers that put specific modules at specific distances. Save it as a .tres
## to share it between paths. Any change re-emits `changed`, so the stitcher
## rebuilds live.

enum Mode { PATTERN, RANDOM }
enum Fit { STRETCH, TRUNCATE_PATTERN, FINISH_CYCLE, NONE }
enum MarkerSnap { EXACT, NEAREST_JOINT }

@export_group("Ends")

## Placed once at the start of the path.
@export var start: PathModule:
	set(value):
		_unwatch(start)
		start = value
		_watch(start)
		emit_changed()

## Placed once at the end of the path.
@export var end: PathModule:
	set(value):
		_unwatch(end)
		end = value
		_watch(end)
		emit_changed()

## Place the end module exactly at the path end, unstretched; only the modules
## before it are fitted.
@export var anchor_end := false:
	set(value):
		anchor_end = value
		emit_changed()

@export_group("Middle")

## PATTERN repeats `pattern` in order; RANDOM draws from `random_entries`.
@export var mode := Mode.PATTERN:
	set(value):
		mode = value
		emit_changed()

## Repeated in order, e.g. Block1 x4 then Block2 x2.
@export var pattern: Array[PathPatternEntry] = []:
	set(value):
		for e in pattern:
			_unwatch(e)
		pattern = value
		for e in pattern:
			_watch(e)
		emit_changed()

## Start the pattern this many modules in, so neighbouring paths can continue
## each other's rhythm.
@export_range(0, 1000, 1, "or_greater") var pattern_offset := 0:
	set(value):
		pattern_offset = value
		emit_changed()

## Weighted choices for RANDOM mode.
@export var random_entries: Array[PathRandomEntry] = []:
	set(value):
		for e in random_entries:
			_unwatch(e)
		random_entries = value
		for e in random_entries:
			_watch(e)
		emit_changed()

## Same seed = same random layout every rebuild.
@export var random_seed := 1:
	set(value):
		random_seed = value
		emit_changed()

## Longest run of the same module in RANDOM mode (0 = unlimited).
@export_range(0, 100, 1, "or_greater") var max_repeat := 0:
	set(value):
		max_repeat = value
		emit_changed()

@export_group("Fit")

## How modules are made to fill the path exactly.
## STRETCH: whole modules, all stretched by the same small factor.
## TRUNCATE_PATTERN: as many whole modules as fit, then stretched to close the gap.
## FINISH_CYCLE: whole pattern cycles only (more stretch, rhythm intact).
## NONE: no stretch; any gap before the end module stays visible.
@export var fit := Fit.STRETCH:
	set(value):
		fit = value
		emit_changed()

@export_group("Markers")

## Modules placed at specific path distances. PathMarker children of the
## Path3D add to these.
@export var markers: Array[PathMarkerEntry] = []:
	set(value):
		for e in markers:
			_unwatch(e)
		markers = value
		for e in markers:
			_watch(e)
		emit_changed()

## EXACT: the marker sits exactly at its distance and the modules either side
## are fitted around it. NEAREST_JOINT: the marker replaces the closest
## sequence module, in that module's slot.
@export var marker_snap := MarkerSnap.EXACT:
	set(value):
		marker_snap = value
		emit_changed()


func _watch(r: Resource) -> void:
	if r and not r.changed.is_connected(emit_changed):
		r.changed.connect(emit_changed)


func _unwatch(r: Resource) -> void:
	if r and r.changed.is_connected(emit_changed):
		r.changed.disconnect(emit_changed)
