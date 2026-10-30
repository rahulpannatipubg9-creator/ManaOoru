extends SceneTree

func _init() -> void:
	var builder := BuildingBuilder.new()
	root.add_child(builder)
	builder.footprints.append(PackedVector2Array([Vector2(0,0),Vector2(30,0),Vector2(30,10),Vector2(0,10)]))
	builder.building_metadata.append({"id":"osm/way/599199178"})
	builder._styles.append({"base":0.0})
	builder._main_road_grid[Vector2i.ZERO] = PackedVector2Array([Vector2(-20,-5),Vector2(40,-5)])
	builder._add_historical_shop_reference_panels()
	var panel := builder.get_node("HistoricalShopReference_599199178") as Label3D
	assert(panel != null)
	assert("Sri Sai Thirumala Kiranam" in panel.text)
	assert("Sri Krishna Clinic" in panel.text)
	assert("Fino Payment Bank" in panel.text)
	assert("individual shop bays unverified" in panel.text)
	assert("building unverified" in panel.text)
	assert(panel.get_meta("capture_date") == "2020-06-11")
	print("PASS historical shop reference panel: matched block, names, date, unlocated warning")
	quit()
