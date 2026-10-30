extends RefCounted
const PATH := "user://graphics.cfg"
const PROFILES := {
	"Low": {"scale": 0.65, "distance": 320.0, "actors": 12, "simulation": 120.0, "shadows": false, "effects": 0.25, "fps": 30, "max_draw_calls": 180, "max_vram_mb": 450.0, "shadow_cascade": 1, "shadow_distance": 0.0},
	"Medium": {"scale": 0.8, "distance": 550.0, "actors": 28, "simulation": 220.0, "shadows": true, "effects": 0.6, "fps": 60, "max_draw_calls": 220, "max_vram_mb": 450.0, "shadow_cascade": 1, "shadow_distance": 35.0},
	"High": {"scale": 1.0, "distance": 850.0, "actors": 55, "simulation": 400.0, "shadows": true, "effects": 1.0, "fps": 60, "max_draw_calls": 250, "max_vram_mb": 450.0, "shadow_cascade": 2, "shadow_distance": 65.0}}
var preset := "Auto"
var values: Dictionary = PROFILES.Medium.duplicate()

func resolve_auto(mobile: bool, memory: int) -> String:
	if mobile: return "Low" if memory <= 4 * 1024 * 1024 * 1024 else "Medium"
	return "High" if memory >= 12 * 1024 * 1024 * 1024 else "Medium"

func select(name: String) -> void:
	preset = name if name in ["Auto", "Low", "Medium", "High", "Custom"] else "Auto"
	if preset == "Custom":
		sanitize()
		return
	var profile := preset
	if profile == "Auto": profile = resolve_auto(OS.has_feature("mobile"), int(OS.get_memory_info().get("physical", 0)))
	values = PROFILES[profile].duplicate()

func sanitize() -> void:
	var defaults: Dictionary = PROFILES.Medium
	for key in defaults:
		var value: Variant = values.get(key, defaults[key])
		if key == "shadows": values[key] = value if value is bool else defaults[key]
		else: values[key] = float(value) if (value is float or value is int) and is_finite(float(value)) else defaults[key]
	values.scale = clampf(values.scale, 0.5, 1.0)
	values.distance = clampf(values.distance, 250.0, 1000.0)
	values.actors = clampi(int(values.actors), 6, 70)
	values.simulation = clampf(values.simulation, 80.0, 450.0)
	values.effects = clampf(values.effects, 0.0, 1.0)
	values.fps = 30 if int(values.fps) < 45 else 60

func load_from(path := PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		select("Auto")
		return
	var stored: Variant = config.get_value("graphics", "values", PROFILES.Medium.duplicate())
	values = stored if stored is Dictionary else PROFILES.Medium.duplicate()
	select(str(config.get_value("graphics", "preset", "Auto")))

func save_to(path := PATH) -> Error:
	sanitize()
	var config := ConfigFile.new()
	config.set_value("graphics", "preset", preset)
	config.set_value("graphics", "values", values)
	return config.save(path)
