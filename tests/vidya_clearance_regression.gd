extends SceneTree
func _init() -> void:
	var clearance := preload("res://scripts/world/vidya_lane_clearance.gd").new()
	clearance.segments = [[Vector2(0,-20),Vector2(0,20),2.0]]
	assert(clearance.excludes(PackedVector2Array([Vector2(-4,-1),Vector2(4,-1),Vector2(4,1),Vector2(-4,1)])),"Cross-road building must be rejected even when all corners are outside")
	assert(not clearance.excludes(PackedVector2Array([Vector2(4,-1),Vector2(8,-1),Vector2(8,1),Vector2(4,1)])),"Roadside houses must remain")
	var data := MapData.load_shared()
	clearance.prepare(data)
	assert(not clearance.segments.is_empty(),"Photo sequence must resolve to mapped road segments")
	var builder := BuildingBuilder.new()
	root.add_child(builder)
	builder.setup(data,clearance.excludes)
	for ring in builder.footprints:
		assert(not clearance.excludes(ring),"Rendered building still blocks the protected lane")
	print("PASS Vidyanagar 2 clearance: crossing footprints rejected, roadside preserved, generated footprint corridor clear")
	quit()
