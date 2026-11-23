@tool
class_name PathSection
extends Resource
## One stretch of a PathStitcher's path: an optional start block, a block pattern
## (repeating in order, or a seeded weighted random draw), and an optional end
## block, fitted to the section's length. A stitcher lays its sections end to end.
## Save it as a .tres to share it between paths. Any change re-emits `changed`,
## so the stitcher rebuilds live.

enum Mode { PATTERN, RANDOM }
enum Fit { STRETCH, TRUNCATE_PATTERN, FINISH_CYCLE, NONE }

## A name for this section, shown in the BUILDING BLOCKS panel.
@export var title := "":
	set(value):
		title = value
		emit_changed()

## How far along the path this section runs (m). 0 = share whatever the other
## sections leave over (several 0-length sections share it equally).
@export_range(0.0, 100000.0, 0.01, "or_greater", "suffix:m") var length := 0.0:
	set(value):
		length = maxf(value, 0.0)
		emit_changed()

@export_group("Ends")

## Placed at the start of the section.
@export var start: PathModule:
	set(value):
		_unwatch(start)
		start = value
		_watch(start)
		emit_changed()

## How many copies of the first block sit at the start.
@export_range(1, 1000, 1, "or_greater") var start_count := 1:
	set(value):
		start_count = maxi(value, 1)
		emit_changed()

## Placed at the end of the section.
@export var end: PathModule:
	set(value):
		_unwatch(end)
		end = value
		_watch(end)
		emit_changed()

## How many copies of the last block sit at the end.
@export_range(1, 1000, 1, "or_greater") var end_count := 1:
	set(value):
		end_count = maxi(value, 1)
		emit_changed()

## Place the last block exactly at the section end, unstretched; only the blocks
## before it are fitted.
@export var anchor_end := false:
	set(value):
		anchor_end = value
		emit_changed()

@export_group("Pattern")

## PATTERN repeats the block sequence in order; RANDOM draws from it, using
## each row's count as its weight.
@export var mode := Mode.PATTERN:
	set(value):
		mode = value
		emit_changed()

## The blocks: in PATTERN mode `count` copies of each in a row, repeated to
## fill the section; in RANDOM mode `count` is the block's weight.
@export var pattern: Array[PathPatternEntry] = []:
	set(value):
		for e in pattern:
			_unwatch(e)
		pattern = value
		for e in pattern:
			_watch(e)
		emit_changed()

## Start the pattern this many blocks in, so neighbouring paths can continue
## each other's rhythm.
@export_range(0, 1000, 1, "or_greater") var pattern_offset := 0:
	set(value):
		pattern_offset = value
		emit_changed()

## Same seed = same random layout every rebuild.
@export var random_seed := 1:
	set(value):
		random_seed = value
		emit_changed()

## Longest run of the same block in RANDOM mode (0 = unlimited).
@export_range(0, 100, 1, "or_greater") var max_repeat := 0:
	set(value):
		max_repeat = value
		emit_changed()

@export_group("Fit")

## How blocks are made to fill the section exactly.
## STRETCH: whole blocks, all stretched by the same small factor.
## TRUNCATE_PATTERN: as many whole blocks as fit, then stretched to close the gap.
## FINISH_CYCLE: whole pattern cycles only (more stretch, rhythm intact).
## NONE: no stretch; any gap before the last block stays visible.
@export var fit := Fit.STRETCH:
	set(value):
		fit = value
		emit_changed()

func _watch(r: Resource) -> void:
	if r and not r.changed.is_connected(emit_changed):
		r.changed.connect(emit_changed)


func _unwatch(r: Resource) -> void:
	if r and r.changed.is_connected(emit_changed):
		r.changed.disconnect(emit_changed)
