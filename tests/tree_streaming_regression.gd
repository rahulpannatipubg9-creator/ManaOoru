extends SceneTree

class ClearBuildings extends BuildingBuilder:
	func is_clear(_point: Vector2, _radius: float) -> bool: return true

class WorldFixture extends Node3D:
	var buildings: BuildingBuilder
	func ground_height(_point: Vector2) -> float: return 0.0

func _init() -> void: call_deferred('_run')

func _run() -> void:
	var world := WorldFixture.new()
	world.buildings = ClearBuildings.new()
	root.add_child(world)
	world.add_child(world.buildings)
	var tree := TreeBuilder.new()
	world.add_child(tree)
	tree.set_process(false)
	tree._world = world
	tree._mesh = TreeBuilder._impostor_mesh()
	tree._billboard_mesh = TreeBuilder._billboard_card()
	tree._material = ShaderMaterial.new()
	tree._billboard_material = ShaderMaterial.new()
	tree._trunk_shape = CylinderShape3D.new()
	tree._trunk_shape.radius = 0.22
	tree._trunk_shape.height = 4.0
	tree._chunks[Vector2i.ZERO] = PackedFloat32Array([10,10,8,5,20,10,12,6])
	tree._chunks[Vector2i(30,30)] = PackedFloat32Array([2890,2890,8,5])
	tree.apply_view_distance(250.0)
	tree._refresh_stream(Vector2.ZERO)
	assert(tree._pending == [Vector2i.ZERO], 'Distant source chunks must not enter the work queue')
	tree._build_chunk(Vector2i.ZERO)
	assert(tree.tree_count == 2, 'Both nearby trees must build')
	var first_chunk: Node3D = tree._stream_nodes[Vector2i.ZERO]
	var first_mesh: MultiMeshInstance3D = first_chunk.get_child(0)
	var first_pose := first_mesh.multimesh.get_instance_transform(0)
	var first_body: RID = first_chunk.get_meta('trunks')
	assert(PhysicsServer3D.body_get_shape_count(first_body) == 2, 'Nearby trunks must retain collision')
	for frame in 2: await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(8,2,10), Vector3(12,2,10))
	var contact := world.get_world_3d().direct_space_state.intersect_ray(ray)
	assert(not contact.is_empty() and contact.rid == first_body, 'A loaded trunk must block a real physics ray')
	tree._refresh_stream(Vector2(2890,2890))
	assert(tree.tree_count == 0 and not tree._built.has(Vector2i.ZERO), 'Travel must unload distant foliage and trunk ownership')
	for frame in 2: await physics_frame
	assert(world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), 'Unloading must remove trunk collision from the physics space')
	tree._build_chunk(Vector2i(30,30))
	assert(tree.tree_count == 1, 'Destination trees must load')
	tree._refresh_stream(Vector2.ZERO)
	tree._build_chunk(Vector2i.ZERO)
	var returned_mesh: MultiMeshInstance3D = tree._stream_nodes[Vector2i.ZERO].get_child(0)
	assert(returned_mesh.multimesh.get_instance_transform(0).is_equal_approx(first_pose), 'Returning must reproduce the same tree transforms')
	# A deliberately expired deadline must stop after one tree, retaining progress.
	tree._chunks[Vector2i(1,0)] = PackedFloat32Array([110,10,8,5,120,10,8,5])
	tree._start_chunk(Vector2i(1,0))
	tree._advance_chunk(1)
	assert(tree._work_active and tree._work_index == 4, 'A chunk must yield between source trees')
	tree._advance_chunk(0)
	assert(tree._built.has(Vector2i(1,0)), 'Yielded chunks must finish without losing entries')
	world.queue_free()
	for i in 5: await process_frame
	print('PASS tree streaming: local queue, trunk collision, unload, deterministic return, resumable work')
	quit()
