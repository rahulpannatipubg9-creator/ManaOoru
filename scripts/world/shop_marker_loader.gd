extends Node3D
## Attach to a Node3D. Set data_path to shop_coordinates.py's output.
## Optional prefab may implement configure_shop(details) and interact().
## Marker roots retain the complete source record as metadata for UI code.
@export_file("*.json") var data_path := ""
@export var marker_prefab: PackedScene

func _ready() -> void:
	if data_path.is_empty():
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if not data is Dictionary:
		push_error("Invalid shop marker data: " + data_path)
		return
	for shop: Dictionary in data.get("shops", []):
		# Reproject GPS with the city's own scale to keep its roads aligned even
		# when the interchange file was generated using 111320 m/degree.
		var point := GeoProjection.lon_lat_to_map(float(shop.longitude), float(shop.latitude))
		if not GeoProjection.is_playable(point):
			continue
		var marker := marker_prefab.instantiate() as Node3D if marker_prefab else Node3D.new()
		if marker == null:
			push_error("Shop marker prefab must have a Node3D root")
			continue
		marker.name = str(shop.name).validate_node_name()
		marker.position = GeoProjection.map_to_world(point, MapData.load_shared().terrain.height_at(point))
		marker.set_meta("shop_details", shop)
		marker.add_to_group("shop_markers")
		add_child(marker)
		if marker.has_method("configure_shop"):
			marker.call("configure_shop", shop)
