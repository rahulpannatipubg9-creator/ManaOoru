extends SceneTree

## Bakes a shop-front signboard for every real named place in
## data/places/godavarikhani_places.json (OpenStreetMap + Overture Maps), with the
## name exactly as published. Writes the boards as a vertical strip of atlas pages
## (imported as a Texture2DArray) plus boards.json telling the building builder
## where each place is and which page/cell holds its board. Text is shaped by
## Godot's text server; fonts are Noto Sans (SIL OFL 1.1), used only to bake.
##
## Run with a window (text needs the renderer), from the project folder:
##   godot --path . --script tools/signboards/make_signboards.gd

const PLACES := "res://data/places/godavarikhani_places.json"
const OUT_DIR := "res://assets/textures/signboards/"
const FONT := "res://tools/signboards/fonts/NotoSans-Black.ttf"
const TELUGU_FONT := "res://tools/signboards/fonts/NotoSansTelugu-Bold.ttf"
const PAGE := 2048
const CELL := Vector2i(384, 84)
const COLUMNS := 5
const ROWS := 24
const PER_PAGE := COLUMNS * ROWS
## Flex-board colours by kind of place: [background, text].
const STYLES := {
	"bank": ["#0b4f8a", "#ffffff"], "finance": ["#123a7a", "#ffd400"],
	"health": ["#f7f7f2", "#c62828"], "pharmacy": ["#0a7c3e", "#ffffff"],
	"food": ["#c8102e", "#ffd400"], "education": ["#1d4f9c", "#ffffff"],
	"worship": ["#f39c12", "#7a1010"], "fuel": ["#1a1a1a", "#ffd400"],
	"government": ["#2e5e3a", "#ffffff"],
}
const SHOP_STYLES := [["#c8102e", "#ffffff"], ["#ffd400", "#b3001b"], ["#1d3f95", "#ffffff"], ["#e4007c", "#ffffff"],
	["#ff6a00", "#ffffff"], ["#5b0b3a", "#f3c55b"], ["#00838f", "#ffffff"], ["#37474f", "#ffffff"], ["#2e7d32", "#fff59d"]]

func _init() -> void:
	var places: Array = JSON.parse_string(FileAccess.get_file_as_string(PLACES)).places
	var user_export: Variant = JSON.parse_string(FileAccess.get_file_as_string(MapData.USER_SHOPS_PATH))
	# Include every named runtime POI, including the user's Overpass import and
	# exact local pins. The old atlas only contained the older place catalogue.
	for poi in MapData.load_shared().pois:
		if str(poi.name).strip_edges().is_empty():
			continue
		var exists := false
		for place: Dictionary in places:
			if str(place.name).to_lower() == str(poi.name).to_lower() and GeoProjection.lon_lat_to_map(float(place.lon), float(place.lat)).distance_to(poi.position) < 40.0:
				exists = true
				break
		if not exists:
			var gps := GeoProjection.map_to_lon_lat(poi.position)
			places.append({"name": poi.name, "category": poi.kind, "lon": gps[0], "lat": gps[1]})
	var font := FontFile.new()
	font.load_dynamic_font(ProjectSettings.globalize_path(FONT))
	# A few published names are in Telugu script.
	var telugu := FontFile.new()
	telugu.load_dynamic_font(ProjectSettings.globalize_path(TELUGU_FONT))
	font.fallbacks = [telugu]
	var pages := ceili(places.size() / float(PER_PAGE))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(PAGE, PAGE)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var strip := Image.create(PAGE, PAGE * pages, false, Image.FORMAT_RGB8)
	var boards := []
	for page in pages:
		for child in viewport.get_children():
			child.free()
		var backdrop := ColorRect.new()
		backdrop.size = Vector2(PAGE, PAGE)
		backdrop.color = Color("#202020")
		viewport.add_child(backdrop)
		for slot in PER_PAGE:
			var index := page * PER_PAGE + slot
			if index >= places.size():
				break
			var place: Dictionary = places[index]
			var origin := Vector2i(slot % COLUMNS * CELL.x, slot / COLUMNS * CELL.y)
			viewport.add_child(_board(place, origin, font))
			var record := place.duplicate(true)
			record.source_features = []
			if user_export is Dictionary:
				for element: Dictionary in user_export.get("elements", []):
					var tags: Dictionary = element.get("tags", {})
					var coordinate: Dictionary = element if element.get("type") == "node" else element.get("center", {})
					if str(tags.get("name", "")).to_lower() != str(place.name).to_lower() or not coordinate.has("lon") or not coordinate.has("lat"):
						continue
					var point := GeoProjection.lon_lat_to_map(float(place.lon), float(place.lat))
					if point.distance_to(GeoProjection.lon_lat_to_map(float(coordinate.lon), float(coordinate.lat))) < 40.0:
						record.source_features.append(element.duplicate(true))
			record.business_id = "%s@%.8f,%.8f" % [str(place.name), float(place.lon), float(place.lat)]
			record.page = page
			record.rect = [origin.x / float(PAGE), origin.y / float(PAGE),
				(origin.x + CELL.x) / float(PAGE), (origin.y + CELL.y) / float(PAGE)]
			boards.append(record)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		for _frame in 4:
			await process_frame
		var image := viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		strip.blit_rect(image, Rect2i(0, 0, PAGE, PAGE), Vector2i(0, PAGE * page))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	strip.save_png(OUT_DIR + "signboards.png")
	var index_file := FileAccess.open(OUT_DIR + "boards.json", FileAccess.WRITE)
	index_file.store_string(JSON.stringify({"pages": pages, "boards": boards}, " "))
	index_file.close()
	_write_import(pages)
	print("baked %d boards on %d pages" % [boards.size(), pages])
	quit()

func _style(place: Dictionary) -> Array:
	var category := str(place.category)
	var kinds := {
		"bank": ["bank", "atm"], "finance": ["financ", "loan", "insurance"],
		"pharmacy": ["pharmac", "drug", "medical"], "health": ["hospital", "clinic", "health", "dentist", "doctor"],
		"food": ["restaurant", "eatery", "cafe", "food", "bakery", "bar", "sweet"],
		"education": ["school", "college", "learning", "education", "librar"],
		"worship": ["worship"], "fuel": ["fuel", "gas_station"], "government": ["government", "police", "post_office"],
	}
	for kind in kinds:
		for word in kinds[kind]:
			if category.contains(word):
				return STYLES[kind]
	return SHOP_STYLES[absi(hash(str(place.name))) % SHOP_STYLES.size()]

func _board(place: Dictionary, origin: Vector2i, font: FontFile) -> Control:
	var colors := _style(place)
	var panel := ColorRect.new()
	panel.position = Vector2(origin)
	panel.size = Vector2(CELL)
	panel.color = Color(colors[0])
	var trim := ColorRect.new()
	trim.position = Vector2(6.0, CELL.y - 9.0)
	trim.size = Vector2(CELL.x - 12.0, 4.0)
	trim.color = Color(colors[1])
	panel.add_child(trim)
	var label := Label.new()
	label.text = str(place.name).to_upper()
	label.position = Vector2(10.0, 4.0)
	label.size = Vector2(CELL.x - 20.0, CELL.y - 16.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = -1
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", Color(colors[1]))
	label.add_theme_constant_override("line_spacing", -6)
	# Largest size that fits: one line if possible, else two.
	var size := 40
	while size > 6:
		var paragraph := TextParagraph.new()
		paragraph.width = label.size.x
		paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND
		paragraph.add_string(label.text, font, size)
		if paragraph.get_size().y <= label.size.y and paragraph.get_size().x <= label.size.x:
			break
		size -= 1
	label.add_theme_font_size_override("font_size", size)
	panel.add_child(label)
	return panel

func _write_import(pages: int) -> void:
	var file := FileAccess.open(OUT_DIR + "signboards.png.import", FileAccess.WRITE)
	file.store_string("""[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="%ssignboards.png"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=1
slices/vertical=%d
""" % [OUT_DIR, pages])
	file.close()
