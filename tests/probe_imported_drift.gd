extends SceneTree
func _init() -> void:
 run.call_deferred()
func run() -> void:
 var game: Node = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 for i in 60: await physics_frame
 var starts := {}
 for car in game.vehicles: starts[car] = car.global_position
 for i in 30: await physics_frame
 for car in game.vehicles:
  var drift: float = car.global_position.distance_to(starts[car])
  if drift > .01:
   print("DRIFT ",car.name," ",drift," from ",starts[car]," to ",car.global_position," velocity ",car.linear_velocity," contacts ",car.get_colliding_bodies().map(func(n):return n.name))
 quit()
