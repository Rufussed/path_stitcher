@tool
class_name PathModule
extends Resource
## One module that a PathSequence can place along a path: a scene file whose
## meshes are deformed along the curve. Same conventions as any source module:
## X along the path, Y up, Z sideways, origin at the centre of X and Z on the
## floor; `Col-` / `ColVis-` name prefixes for collision.

## The module scene (.blend, .glb, .gltf or .tscn).
@export var scene: PackedScene:
	set(value):
		scene = value
		emit_changed()

## Joint-to-joint length along the path (m). 0 = automatic: the mesh's X
## extent minus `overlap` at each end.
@export_range(0.0, 1000.0, 0.01, "or_greater", "suffix:m") var length := 0.0:
	set(value):
		length = value
		emit_changed()

## Built-in overlap at each end (m), e.g. 0.5 for a 6 m Block1 placed every 5 m.
@export_range(0.0, 100.0, 0.01, "or_greater", "suffix:m") var overlap := 0.0:
	set(value):
		overlap = value
		emit_changed()


## Short display name for summaries.
func display_name() -> String:
	if scene == null:
		return "(empty)"
	return scene.resource_path.get_file().get_basename()
