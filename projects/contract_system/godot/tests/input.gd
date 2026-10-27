extends SceneTree
var runner: RefCounted
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var game = load("res://Main.tscn").instantiate()
 root.add_child(game)
 runner = load("res://qa/input.gd").new()
 runner.run(game)
