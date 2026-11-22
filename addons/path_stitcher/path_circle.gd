@tool
class_name PathCircle
extends Path3D
## A Path3D that builds a flat circle from one setting, so you do not have to place
## points by hand. Change `radius` and the curve is rebuilt; a PathStitcher on this
## path follows it live. Move, rotate or scale the node to place the circle.
## Optional: any Path3D works with a PathStitcher.
##
## The path runs anticlockwise seen from above, so the outside of the circle is the path's right, which is where
## a block's +Z side faces (see PathStitcher's Flip Side). It ends where it starts.

## Radius of the circle.
@export_range(1.0, 500.0, 0.01, "or_greater", "suffix:m") var radius := 20.0:
	set(v):
		radius = maxf(v, 0.01)
		if is_node_ready():
			build()

## Rebuild the curve now.
@export_tool_button("Rebuild curve", "Reload") var rebuild_action = build


func _ready() -> void:
	if curve == null or curve.point_count < 2:
		build()


## Replaces the curve with a circle of the current radius: four Bezier points
## (the standard circle approximation) plus a last point on top of the first.
func build() -> void:
	var c := Curve3D.new()
	var k := radius * 0.5522847498 # Bezier handle length for a quarter circle
	var corners := [Vector3(radius, 0, 0), Vector3(0, 0, -radius), Vector3(-radius, 0, 0), Vector3(0, 0, radius), Vector3(radius, 0, 0)]
	var tangents := [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1)]
	for i in corners.size():
		c.add_point(corners[i], -tangents[i] * k, tangents[i] * k)
	curve = c
