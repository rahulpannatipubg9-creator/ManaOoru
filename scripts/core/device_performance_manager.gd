class_name DevicePerformanceManager
extends Node

## Hardware-Aware Device Optimization Manager (BGMI / OnePlus Style).
## Inspects GPU, CPU, RAM, and screen refresh rate at boot, automatically
## classifies the hardware into 4 performance tiers, saves the configuration
## to user://settings.cfg, and applies optimal engine and render settings.

enum DeviceTier {
	TIER_1_BUDGET_MOBILE = 1,
	TIER_2_MID_RANGE = 2,
	TIER_3_FLAGSHIP_KILLER = 3,
	TIER_4_PRO_TABLET_DESKTOP = 4
}

const SETTINGS_PATH := "user://settings.cfg"

## Keywords identifying Tier 1: Budget Mobile (Mali-G52/G57, Adreno 610/619, Helio G95/G99, Snapdragon 680/695)
const TIER_1_GPU_PATTERNS := [
	"mali-g52", "mali-g57", "mali-g51", "mali-g71", "mali-g72", "mali-t", "mali-400", "mali-450",
	"adreno (tm) 610", "adreno 610", "adreno (tm) 612", "adreno 612",
	"adreno (tm) 615", "adreno 615", "adreno (tm) 616", "adreno 616",
	"adreno (tm) 618", "adreno 618", "adreno (tm) 619", "adreno 619",
	"adreno (tm) 505", "adreno (tm) 506", "adreno (tm) 508", "adreno (tm) 509", "adreno (tm) 512",
	"adreno 505", "adreno 506", "adreno 508", "adreno 509", "adreno 512",
	"powervr", "ge8320", "ge8300"
]

const TIER_1_SOC_PATTERNS := [
	"helio g80", "helio g85", "helio g88", "helio g90", "helio g95", "helio g96", "helio g99",
	"snapdragon 680", "snapdragon 685", "snapdragon 695", "snapdragon 4", "sm6225", "sm6375"
]

## Keywords identifying Tier 3: Upper Mid-Range & Flagship Killers (OnePlus 10R/11R, Poco X6 Pro, Snapdragon 8+ Gen 1, Dimensity 8300)
const TIER_3_GPU_PATTERNS := [
	"adreno (tm) 660", "adreno 660", "adreno (tm) 730", "adreno 730",
	"adreno (tm) 740", "adreno 740", "adreno (tm) 750", "adreno 750",
	"mali-g610", "mali-g615", "mali-g710", "mali-g715", "mali-g720", "immortalis"
]

const TIER_3_SOC_PATTERNS := [
	"snapdragon 8 gen", "snapdragon 8+ gen", "sm8475", "sm8550", "sm8650",
	"dimensity 8300", "dimensity 9000", "dimensity 9200", "dimensity 9300",
	"oneplus 10r", "oneplus 11r", "poco x6 pro", "apple a16", "apple a17", "apple a18"
]

## Keywords identifying Tier 2: Mid-Range Baseline (OnePlus 8T/9R, Snapdragon 778G/870, Dimensity 7200, base iPhones)
const TIER_2_GPU_PATTERNS := [
	"adreno (tm) 640", "adreno 640", "adreno (tm) 642", "adreno 642",
	"adreno (tm) 643", "adreno 643", "adreno (tm) 650", "adreno 650",
	"mali-g68", "mali-g76", "mali-g77", "mali-g78"
]

const TIER_2_SOC_PATTERNS := [
	"snapdragon 778", "snapdragon 865", "snapdragon 870", "sm7325", "sm8250",
	"dimensity 7200", "dimensity 8000", "dimensity 8100", "dimensity 1080", "dimensity 920", "dimensity 7050",
	"oneplus 8t", "oneplus 9r", "apple a12", "apple a13", "apple a14", "apple a15"
]

## Keywords identifying Tier 4: Tablets, Pro Flagships & Laptops (Apple Silicon M1/M2 Mac, Desktop PC, iPad Pro)
const TIER_4_PATTERNS := [
	"apple m1", "apple m2", "apple m3", "apple m4", "m1 pro", "m1 max", "m2 pro", "m2 max",
	"geforce", "rtx", "gtx", "radeon", "rx 5", "rx 6", "rx 7", "intel arc", "iris xe"
]

var hardware_info: Dictionary = {}
var detected_tier := DeviceTier.TIER_2_MID_RANGE
var active_tier := DeviceTier.TIER_2_MID_RANGE
var active_profile: Dictionary = {}
var is_first_launch := true
var has_manual_override := false
var game: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Setup called from main.gd during startup.
func setup(owner_game: Node) -> void:
	game = owner_game
	hardware_info = detect_hardware()
	var config := load_settings()
	if config.has("device_profile") and not is_first_launch and config.device_profile.get("manual_override", false):
		has_manual_override = true
		active_tier = int(config.device_profile.get("selected_tier", detected_tier)) as DeviceTier
		active_profile = get_profile_for_tier(active_tier, hardware_info)
	else:
		detected_tier = classify_device(hardware_info) as DeviceTier
		active_tier = detected_tier
		has_manual_override = false
		active_profile = get_profile_for_tier(active_tier, hardware_info)
		save_settings(active_profile, false)
	apply_profile(game, active_profile)

## Query GPU, RAM, CPU, screen refresh rate, resolution and aspect ratio.
static func detect_hardware() -> Dictionary:
	var gpu_adapter := RenderingServer.get_video_adapter_name()
	var mem_info := OS.get_memory_info()
	var physical_mem := int(mem_info.get("physical", 0))
	var mem_gb := float(physical_mem) / (1024.0 * 1024.0 * 1024.0)
	var cpu_count := OS.get_processor_count()
	var refresh_rate := DisplayServer.screen_get_refresh_rate()
	if refresh_rate <= 0.0 or is_nan(refresh_rate):
		refresh_rate = 60.0

	var screen_size := Vector2(DisplayServer.screen_get_size())
	if screen_size.x <= 0 or screen_size.y <= 0:
		screen_size = Vector2(DisplayServer.window_get_size())
	if screen_size.x <= 0 or screen_size.y <= 0:
		screen_size = Vector2(1280, 720)

	var max_dim := maxf(screen_size.x, screen_size.y)
	var min_dim := minf(screen_size.x, screen_size.y)
	var aspect_ratio := max_dim / maxf(1.0, min_dim)
	var dpi := float(DisplayServer.screen_get_dpi())
	var is_mobile := OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	var is_desktop := OS.has_feature("pc") or OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linux")
	var is_apple_silicon := OS.has_feature("macos") and (gpu_adapter.to_lower().contains("apple") or OS.get_processor_name().to_lower().contains("apple"))
	
	var is_tablet := false
	if dpi > 0.0 and (screen_size.length() / dpi) >= 7.0:
		is_tablet = true
	elif is_mobile and aspect_ratio <= 1.65 and max_dim >= 1200.0:
		is_tablet = true

	var is_high_res_tablet := is_tablet and (max_dim >= 2400.0 or min_dim >= 1500.0)

	return {
		"gpu_adapter": gpu_adapter,
		"cpu_cores": cpu_count,
		"physical_ram_bytes": physical_mem,
		"physical_ram_gb": mem_gb,
		"screen_refresh_rate": refresh_rate,
		"screen_size": screen_size,
		"screen_dpi": dpi,
		"aspect_ratio": aspect_ratio,
		"is_tablet": is_tablet,
		"is_high_res_tablet": is_high_res_tablet,
		"is_mobile": is_mobile,
		"is_desktop": is_desktop,
		"is_apple_silicon": is_apple_silicon
	}

## Classify hardware info into one of 4 tiers.
static func classify_device(hw: Dictionary) -> int:
	var gpu := str(hw.get("gpu_adapter", "")).to_lower()
	var proc_name := OS.get_processor_name().to_lower()
	var combined_str := gpu + " " + proc_name
	var mem_gb := float(hw.get("physical_ram_gb", 0.0))
	var cpu_cores := int(hw.get("cpu_cores", 4))
	var is_mobile := bool(hw.get("is_mobile", false))
	var is_desktop := bool(hw.get("is_desktop", false))
	var is_tablet := bool(hw.get("is_tablet", false))
	var is_apple := bool(hw.get("is_apple_silicon", false))

	# Desktop PC, Apple Silicon Mac or Pro Desktop
	if is_apple or (is_desktop and not is_mobile):
		for pattern in TIER_4_PATTERNS:
			if combined_str.contains(pattern):
				return DeviceTier.TIER_4_PRO_TABLET_DESKTOP
		if mem_gb >= 6.0 or cpu_cores >= 6:
			return DeviceTier.TIER_4_PRO_TABLET_DESKTOP

	# Check Pro / Flagship Tablet
	if is_tablet and (mem_gb >= 6.0 or hw.get("is_high_res_tablet", false)):
		return DeviceTier.TIER_4_PRO_TABLET_DESKTOP

	# Tier 1: Budget Mobile check (Mali-G52/G57, Adreno 610/619, Helio G95/G99, Snapdragon 680/695)
	for pattern in TIER_1_GPU_PATTERNS:
		if combined_str.contains(pattern):
			return DeviceTier.TIER_1_BUDGET_MOBILE
	for pattern in TIER_1_SOC_PATTERNS:
		if combined_str.contains(pattern):
			return DeviceTier.TIER_1_BUDGET_MOBILE
	if is_mobile and (mem_gb > 0.0 and mem_gb <= 4.2):
		return DeviceTier.TIER_1_BUDGET_MOBILE

	# Tier 2: Mid-Range Baseline SoCs check (e.g. Dimensity 7200, Snapdragon 778G/870, OnePlus 8T/9R)
	for pattern in TIER_2_SOC_PATTERNS:
		if combined_str.contains(pattern):
			return DeviceTier.TIER_2_MID_RANGE

	# Tier 3: Upper Mid-Range & Flagship Killers (OnePlus 10R/11R, Poco X6 Pro, Snapdragon 8+ Gen 1, Dimensity 8300)
	for pattern in TIER_3_GPU_PATTERNS:
		if combined_str.contains(pattern):
			return DeviceTier.TIER_3_FLAGSHIP_KILLER
	for pattern in TIER_3_SOC_PATTERNS:
		if combined_str.contains(pattern):
			return DeviceTier.TIER_3_FLAGSHIP_KILLER
	if is_mobile and mem_gb >= 11.5:
		return DeviceTier.TIER_3_FLAGSHIP_KILLER

	# Tier 2: Mid-Range Baseline GPUs
	for pattern in TIER_2_GPU_PATTERNS:
		if combined_str.contains(pattern):
			return DeviceTier.TIER_2_MID_RANGE

	# Fallbacks based on RAM / Cores
	if is_mobile:
		if mem_gb >= 8.0 and cpu_cores >= 8:
			return DeviceTier.TIER_3_FLAGSHIP_KILLER
		return DeviceTier.TIER_2_MID_RANGE

	return DeviceTier.TIER_4_PRO_TABLET_DESKTOP

## Generate the complete performance profile dictionary for a given tier.
static func get_profile_for_tier(tier: int, hw: Dictionary) -> Dictionary:
	var refresh_rate := float(hw.get("screen_refresh_rate", 60.0))
	var is_high_res_tablet := bool(hw.get("is_high_res_tablet", false))
	var is_desktop := bool(hw.get("is_desktop", false))
	var aspect_ratio := float(hw.get("aspect_ratio", 1.777))
	var is_tablet := bool(hw.get("is_tablet", false))

	match tier:
		DeviceTier.TIER_1_BUDGET_MOBILE:
			return {
				"tier": DeviceTier.TIER_1_BUDGET_MOBILE,
				"tier_name": "Tier 1: Budget Mobile",
				"target_fps": 30,
				"scaling_3d_scale": 0.65,
				"shadow_enabled": false,
				"directional_shadow_mode": DirectionalLight3D.SHADOW_ORTHOGONAL,
				"directional_shadow_max_distance": 0.0,
				"view_distance": 320.0,
				"simulation_distance": 120.0,
				"actors": 12,
				"effects": 0.25,
				"tablet_hud_inset": false
			}

		DeviceTier.TIER_2_MID_RANGE:
			return {
				"tier": DeviceTier.TIER_2_MID_RANGE,
				"tier_name": "Tier 2: Mid-Range Baseline",
				"target_fps": 60,
				"scaling_3d_scale": 0.80,
				"shadow_enabled": true,
				"directional_shadow_mode": DirectionalLight3D.SHADOW_ORTHOGONAL, # 1-cascade
				"directional_shadow_max_distance": 35.0, # 35 meters
				"view_distance": 550.0,
				"simulation_distance": 220.0,
				"actors": 28,
				"effects": 0.60,
				"tablet_hud_inset": false
			}

		DeviceTier.TIER_3_FLAGSHIP_KILLER:
			var target_fps := 90 if refresh_rate >= 89.0 else 60
			return {
				"tier": DeviceTier.TIER_3_FLAGSHIP_KILLER,
				"tier_name": "Tier 3: Upper Mid-Range & Flagship Killers",
				"target_fps": target_fps,
				"scaling_3d_scale": 0.85,
				"shadow_enabled": true,
				"directional_shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, # 2-cascade
				"directional_shadow_max_distance": 65.0,
				"view_distance": 750.0,
				"simulation_distance": 320.0,
				"actors": 45,
				"effects": 0.85,
				"tablet_hud_inset": false
			}

		DeviceTier.TIER_4_PRO_TABLET_DESKTOP, _:
			var target_fps := 120 if refresh_rate >= 119.0 else 60
			# Cap at 0.75 on 3K+ tablets to prevent thermal throttling; 1.0 (Native) on Desktop/M1 Mac
			var scale := 0.75 if (is_high_res_tablet and not is_desktop) else 1.0
			var tablet_inset := (is_tablet or aspect_ratio <= 1.65)
			return {
				"tier": DeviceTier.TIER_4_PRO_TABLET_DESKTOP,
				"tier_name": "Tier 4: Tablets, Pro Flagships & Laptops",
				"target_fps": target_fps,
				"scaling_3d_scale": scale,
				"shadow_enabled": true,
				"directional_shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
				"directional_shadow_max_distance": 100.0,
				"view_distance": 900.0,
				"simulation_distance": 400.0,
				"actors": 55,
				"effects": 1.0,
				"tablet_hud_inset": tablet_inset
			}

## Apply profile settings to engine, viewport, directional lights, and controllers.
func apply_profile(target_game: Node, profile: Dictionary) -> void:
	if not is_instance_valid(target_game):
		return

	# Target Frame Rate
	Engine.max_fps = int(profile.get("target_fps", 60))

	# 3D Viewport Scale (2D HUD stays at 100% native resolution via canvas_items stretch mode)
	var viewport := target_game.get_viewport()
	if viewport:
		viewport.scaling_3d_scale = float(profile.get("scaling_3d_scale", 1.0))

	# Configure Real-Time Shadows on DirectionalLight3D ("Sun" or any Light3D in scene)
	var shadow_on := bool(profile.get("shadow_enabled", true))
	var shadow_mode: int = int(profile.get("directional_shadow_mode", DirectionalLight3D.SHADOW_ORTHOGONAL))
	var shadow_dist := float(profile.get("directional_shadow_max_distance", 35.0))

	for light: Light3D in target_game.find_children("*", "Light3D", true, false):
		light.shadow_enabled = shadow_on
		if light is DirectionalLight3D and shadow_on:
			light.directional_shadow_mode = shadow_mode
			if shadow_dist > 0.0:
				light.directional_shadow_max_distance = shadow_dist

	# Sync with PerformanceController if present
	if target_game.get("performance_controller") != null and target_game.performance_controller != null:
		var pc = target_game.performance_controller
		if pc.get("settings") != null and pc.settings != null:
			pc.settings.values.scale = profile.get("scaling_3d_scale", 1.0)
			pc.settings.values.fps = profile.get("target_fps", 60)
			pc.settings.values.shadows = shadow_on
			pc.settings.values.distance = profile.get("view_distance", 550.0)
			pc.settings.values.actors = profile.get("actors", 28)
			pc.settings.values.simulation = profile.get("simulation_distance", 220.0)
			pc.settings.values.effects = profile.get("effects", 0.6)
			pc.settings.values["shadow_cascade"] = 1 if shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL else (2 if shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS else 4)
			pc.settings.values["shadow_distance"] = shadow_dist
			pc.apply_settings()

	# Tablet Ergonomics: Update HUD touch layout
	if target_game.get("hud") != null and target_game.hud != null:
		if target_game.hud.has_method("set_tablet_ergonomics_inset"):
			target_game.hud.set_tablet_ergonomics_inset(profile.get("tablet_hud_inset", false))

## Read settings from user://settings.cfg.
func load_settings(path: String = SETTINGS_PATH) -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(path)
	if err != OK:
		is_first_launch = true
		return {}

	is_first_launch = false
	var result := {}
	for section in config.get_sections():
		var sec_dict := {}
		for key in config.get_section_keys(section):
			sec_dict[key] = config.get_value(section, key)
		result[section] = sec_dict
	return result

## Save device profile and settings to user://settings.cfg.
func save_settings(profile: Dictionary, manual: bool = false, path: String = SETTINGS_PATH) -> Error:
	var config := ConfigFile.new()
	config.load(path) # preserve other user settings if present

	config.set_value("device_profile", "detected_tier", int(detected_tier))
	config.set_value("device_profile", "selected_tier", int(profile.get("tier", detected_tier)))
	config.set_value("device_profile", "tier_name", str(profile.get("tier_name", "")))
	config.set_value("device_profile", "gpu_adapter", str(hardware_info.get("gpu_adapter", "")))
	config.set_value("device_profile", "cpu_cores", int(hardware_info.get("cpu_cores", 0)))
	config.set_value("device_profile", "physical_ram_mb", int(hardware_info.get("physical_ram_bytes", 0) / (1024 * 1024)))
	config.set_value("device_profile", "screen_refresh_hz", float(hardware_info.get("screen_refresh_rate", 60.0)))
	config.set_value("device_profile", "is_first_launch", false)
	config.set_value("device_profile", "manual_override", manual)

	config.set_value("performance", "target_fps", int(profile.get("target_fps", 60)))
	config.set_value("performance", "scaling_3d_scale", float(profile.get("scaling_3d_scale", 1.0)))
	config.set_value("performance", "shadow_enabled", bool(profile.get("shadow_enabled", true)))
	config.set_value("performance", "directional_shadow_mode", int(profile.get("directional_shadow_mode", 0)))
	config.set_value("performance", "directional_shadow_max_distance", float(profile.get("directional_shadow_max_distance", 35.0)))
	config.set_value("performance", "view_distance", float(profile.get("view_distance", 550.0)))
	config.set_value("performance", "simulation_distance", float(profile.get("simulation_distance", 220.0)))
	config.set_value("performance", "actors", int(profile.get("actors", 28)))
	config.set_value("performance", "tablet_hud_inset", bool(profile.get("tablet_hud_inset", false)))

	has_manual_override = manual
	return config.save(path)

## Player manual override from settings menu.
func override_tier(tier: int, target_game: Node = null) -> void:
	active_tier = tier as DeviceTier
	has_manual_override = true
	active_profile = get_profile_for_tier(active_tier, hardware_info)
	var target = target_game if target_game != null else game
	if target:
		apply_profile(target, active_profile)
	save_settings(active_profile, true)
