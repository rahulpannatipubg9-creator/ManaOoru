extends RefCounted
## Exclude conflicting render footprints, never edit the geographic source.
var segments: Array = []
var excluded_count := 0

func prepare(data: MapData) -> void:
	segments.clear()
	excluded_count = 0
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/local/vidyanagar2_photo_sequence.json"))
	var references := PackedVector2Array()
	for gps in doc.camera_points_lat_lon:
		references.append(GeoProjection.lon_lat_to_map(gps[1],gps[0]))
	for road in data.roads:
		if road.kind != "residential":
			continue
		for i in range(1,road.points.size()):
			var a: Vector2 = road.points[i-1]
			var b: Vector2 = road.points[i]
			var middle := (a+b)*.5
			for j in range(1,references.size()):
				if middle.distance_to(Geometry2D.get_closest_point_to_segment(middle,references[j-1],references[j]))<12.0:
					segments.append([a,b,RoadStyle.width(road)*.5+.15])
					break

func excludes(points: PackedVector2Array) -> bool:
	for segment in segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var half: float = segment[2]
		if Geometry2D.is_point_in_polygon(a,points) or Geometry2D.is_point_in_polygon(b,points):
			excluded_count += 1
			return true
		for i in points.size():
			var c := points[i]
			var d := points[(i+1)%points.size()]
			if Geometry2D.segment_intersects_segment(a,b,c,d) != null or minf(c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b)),minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d)),b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d)))) < half:
				excluded_count += 1
				return true
	return false
