extends Node3D
## Scene root. Holds the game's tuning parameters; select this node to tune
## everything in one place during playtesting.

@export var params: GameParams:
	set(value):
		params = value
		GameParams.set_active(value)


func _enter_tree() -> void:
	GameParams.set_active(params)
