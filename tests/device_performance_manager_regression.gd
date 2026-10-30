extends SceneTree

const DevicePerformanceManager := preload("res://scripts/core/device_performance_manager.gd")
const TEST_SETTINGS_PATH := "user://test_device_settings.cfg"

var _failures := 0

func _init() -> void:
	run.call_deferred()

func run() -> void:
	_test_module_and_detection()
	_test_tier_classification()
	_test_profiles()
	_test_settings_persistence()
	_test_apply_to_nodes()

	# Clean up temporary test settings file
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))

	if _failures > 0:
		print("FAIL: device performance manager regression: %d test(s) failed" % _failures)
		quit(1)
		return

	print("PASS device performance manager: hardware detection, 4-tier classification (Budget 30 FPS, Mid 60 FPS, Flagship 90 FPS, Pro 120 FPS/3K Tablet), settings.cfg persistence, shadow cascades, and tablet ergonomics")
	quit(0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)

func _test_module_and_detection() -> void:
	var dpm := DevicePerformanceManager.new()
	_check(dpm != null, "DevicePerformanceManager must instantiate")
	var hw := DevicePerformanceManager.detect_hardware()
	_check(hw.has("gpu_adapter"), "Hardware info must include gpu_adapter")
	_check(hw.has("cpu_cores") and hw.cpu_cores > 0, "Hardware info must report CPU cores")
	_check(hw.has("physical_ram_bytes"), "Hardware info must report physical RAM")
	_check(hw.has("screen_refresh_rate") and hw.screen_refresh_rate > 0.0, "Hardware info must report screen refresh rate")
	_check(hw.has("aspect_ratio") and hw.aspect_ratio > 0.0, "Hardware info must report aspect ratio")
	dpm.free()

func _test_tier_classification() -> void:
	# Tier 1: Budget Mobile (Mali-G52/G57, Adreno 610/619, Helio G95/G99, Snapdragon 680/695)
	var t1_adreno := {
		"gpu_adapter": "Adreno (TM) 619",
		"cpu_cores": 8,
		"physical_ram_gb": 4.0,
		"is_mobile": true,
		"is_desktop": false,
		"is_tablet": false,
		"screen_refresh_rate": 60.0
	}
	_check(DevicePerformanceManager.classify_device(t1_adreno) == DevicePerformanceManager.DeviceTier.TIER_1_BUDGET_MOBILE, "Adreno 619 must classify as Tier 1")

	var t1_mali := {
		"gpu_adapter": "Mali-G57 MC2",
		"cpu_cores": 8,
		"physical_ram_gb": 4.0,
		"is_mobile": true,
		"is_desktop": false,
		"is_tablet": false,
		"screen_refresh_rate": 60.0
	}
	_check(DevicePerformanceManager.classify_device(t1_mali) == DevicePerformanceManager.DeviceTier.TIER_1_BUDGET_MOBILE, "Mali-G57 must classify as Tier 1")

	var t1_helio := {
		"gpu_adapter": "Mali-G76 MC4 Helio G95",
		"cpu_cores": 8,
		"physical_ram_gb": 6.0,
		"is_mobile": true,
		"is_desktop": false,
		"is_tablet": false,
		"screen_refresh_rate": 60.0
	}
	_check(DevicePerformanceManager.classify_device(t1_helio) == DevicePerformanceManager.DeviceTier.TIER_1_BUDGET_MOBILE, "Helio G95 must classify as Tier 1")

	# Tier 2: Mid-Range Baseline (OnePlus 8T/9R, Snapdragon 778G/870, Dimensity 7200, base iPhones)
	var t2_snapdragon := {
		"gpu_adapter": "Adreno (TM) 650", # Snapdragon 865/870 / OnePlus 8T / 9R
		"cpu_cores": 8,
		"physical_ram_gb": 8.0,
		"is_mobile": true,
		"is_desktop": false,
		"is_tablet": false,
		"screen_refresh_rate": 120.0
	}
	_check(DevicePerformanceManager.classify_device(t2_snapdragon) == DevicePerformanceManager.DeviceTier.TIER_2_MID_RANGE, "Adreno 650 / OnePlus 8T must classify as Tier 2")

	var t2_dimensity := {
		"gpu_adapter": "Mali-G610 MC4 Dimensity 7200",
		"cpu_cores": 8,
		"physical_ram_gb": 8.0,
		"is_mobile": true,
		"is_desktop": false,
		"is_tablet": false,
		"screen_refresh_rate": 120.0
	}
	_check(DevicePerformanceManager.classify_device(t2_dimensity) == DevicePerformanceManager.DeviceTier.TIER_2_MID_RANGE, "Dimensity 7200 must classify as Tier 2")

	# Tier 3: Upper Mid-Range & Flagship Killers (OnePlus 10R/11R, Poco X6 Pro, Snapdragon 8+ Gen 1, Dimensity 8300)
	var t3_adreno := {
		"gpu_adapter": "Adreno (TM) 730", # Snapdragon 8+ Gen 1 / OnePlus 10R / 11R
		"cpu_cores": 8,
		"physical_ram_gb": 12.0,
		"is_mobile": true,
		"is_desktop": false,
		"is_tablet": false,
		"screen_refresh_rate": 120.0
	}
	_check(DevicePerformanceManager.classify_device(t3_adreno) == DevicePerformanceManager.DeviceTier.TIER_3_FLAGSHIP_KILLER, "Adreno 730 must classify as Tier 3")

	var t3_dimensity := {
		"gpu_adapter": "Mali-G615 MC6 Dimensity 8300", # Poco X6 Pro
		"cpu_cores": 8,
		"physical_ram_gb": 12.0,
		"is_mobile": true,
		"is_desktop": false,
		"is_tablet": false,
		"screen_refresh_rate": 120.0
	}
	_check(DevicePerformanceManager.classify_device(t3_dimensity) == DevicePerformanceManager.DeviceTier.TIER_3_FLAGSHIP_KILLER, "Dimensity 8300 / Poco X6 Pro must classify as Tier 3")

	# Tier 4: Tablets, Pro Flagships & Laptops (Apple Silicon M1/M2 Mac, Desktop PC, Xiaomi Pad 7)
	var t4_mac := {
		"gpu_adapter": "Apple M1",
		"cpu_cores": 8,
		"physical_ram_gb": 16.0,
		"is_mobile": false,
		"is_desktop": true,
		"is_apple_silicon": true,
		"is_tablet": false,
		"screen_refresh_rate": 60.0
	}
	_check(DevicePerformanceManager.classify_device(t4_mac) == DevicePerformanceManager.DeviceTier.TIER_4_PRO_TABLET_DESKTOP, "Apple M1 Mac must classify as Tier 4")

	var t4_pc := {
		"gpu_adapter": "NVIDIA GeForce RTX 4070",
		"cpu_cores": 16,
		"physical_ram_gb": 32.0,
		"is_mobile": false,
		"is_desktop": true,
		"is_apple_silicon": false,
		"is_tablet": false,
		"screen_refresh_rate": 144.0
	}
	_check(DevicePerformanceManager.classify_device(t4_pc) == DevicePerformanceManager.DeviceTier.TIER_4_PRO_TABLET_DESKTOP, "RTX 4070 PC must classify as Tier 4")

	var t4_pad := {
		"gpu_adapter": "Adreno (TM) 730",
		"cpu_cores": 8,
		"physical_ram_gb": 8.0,
		"is_mobile": true,
		"is_desktop": false,
		"is_tablet": true,
		"is_high_res_tablet": true,
		"aspect_ratio": 1.6, # 16:10 Xiaomi Pad 7
		"screen_refresh_rate": 144.0
	}
	_check(DevicePerformanceManager.classify_device(t4_pad) == DevicePerformanceManager.DeviceTier.TIER_4_PRO_TABLET_DESKTOP, "Xiaomi Pad 7 high-res tablet must classify as Tier 4")

func _test_profiles() -> void:
	# Tier 1 Profile
	var hw_60hz := {"screen_refresh_rate": 60.0, "is_desktop": false, "is_high_res_tablet": false, "aspect_ratio": 2.0}
	var p1 := DevicePerformanceManager.get_profile_for_tier(DevicePerformanceManager.DeviceTier.TIER_1_BUDGET_MOBILE, hw_60hz)
	_check(p1.target_fps == 30, "Tier 1 target FPS must be 30")
	_check(is_equal_approx(p1.scaling_3d_scale, 0.65), "Tier 1 scaling_3d_scale must be 0.65 (Internal 720p)")
	_check(not p1.shadow_enabled, "Tier 1 shadows must be disabled")

	# Tier 2 Profile
	var p2 := DevicePerformanceManager.get_profile_for_tier(DevicePerformanceManager.DeviceTier.TIER_2_MID_RANGE, hw_60hz)
	_check(p2.target_fps == 60, "Tier 2 target FPS must be 60")
	_check(is_equal_approx(p2.scaling_3d_scale, 0.80), "Tier 2 scaling_3d_scale must be 0.80 (Internal ~850p)")
	_check(p2.shadow_enabled, "Tier 2 shadows must be enabled")
	_check(p2.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "Tier 2 must use 1-cascade orthogonal shadow")
	_check(is_equal_approx(p2.directional_shadow_max_distance, 35.0), "Tier 2 directional shadow range must be 35 meters")

	# Tier 3 Profile (90 FPS on 90Hz+ screens)
	var hw_120hz := {"screen_refresh_rate": 120.0, "is_desktop": false, "is_high_res_tablet": false, "aspect_ratio": 2.0}
	var p3_high_hz := DevicePerformanceManager.get_profile_for_tier(DevicePerformanceManager.DeviceTier.TIER_3_FLAGSHIP_KILLER, hw_120hz)
	_check(p3_high_hz.target_fps == 90, "Tier 3 target FPS must unlock to 90 on 120Hz screens")
	_check(is_equal_approx(p3_high_hz.scaling_3d_scale, 0.85), "Tier 3 scaling_3d_scale must be 0.85 (Internal 1080p)")
	_check(p3_high_hz.shadow_enabled, "Tier 3 shadows must be enabled")

	var p3_60hz := DevicePerformanceManager.get_profile_for_tier(DevicePerformanceManager.DeviceTier.TIER_3_FLAGSHIP_KILLER, hw_60hz)
	_check(p3_60hz.target_fps == 60, "Tier 3 target FPS must stay at 60 on 60Hz screens")

	# Tier 4 Profile
	var hw_tablet_3k := {
		"screen_refresh_rate": 144.0,
		"is_desktop": false,
		"is_tablet": true,
		"is_high_res_tablet": true,
		"aspect_ratio": 1.6 # 16:10
	}
	var p4_tablet := DevicePerformanceManager.get_profile_for_tier(DevicePerformanceManager.DeviceTier.TIER_4_PRO_TABLET_DESKTOP, hw_tablet_3k)
	_check(p4_tablet.target_fps == 60, "Tier 4 mobile tablet target FPS must cap at 60 FPS to prevent thermal throttling")
	_check(is_equal_approx(p4_tablet.scaling_3d_scale, 0.55), "Tier 4 3K+ tablet scale must cap at 0.55 (~1080p equivalent) to prevent fillrate bottlenecks")
	_check(p4_tablet.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "Tier 4 mobile tablet must use 1-cascade orthogonal shadow")
	_check(is_equal_approx(p4_tablet.directional_shadow_max_distance, 35.0), "Tier 4 mobile tablet shadow distance must be 35 meters")
	_check(is_equal_approx(p4_tablet.view_distance, 550.0), "Tier 4 mobile tablet view distance must be 550 meters")
	_check(p4_tablet.tablet_hud_inset == true, "Tier 4 tablet with 16:10 aspect ratio must enable tablet HUD inset ergonomics")

	var hw_desktop_pc := {
		"screen_refresh_rate": 60.0,
		"is_desktop": true,
		"is_tablet": false,
		"is_high_res_tablet": false,
		"aspect_ratio": 1.777
	}
	var p4_desktop := DevicePerformanceManager.get_profile_for_tier(DevicePerformanceManager.DeviceTier.TIER_4_PRO_TABLET_DESKTOP, hw_desktop_pc)
	_check(is_equal_approx(p4_desktop.scaling_3d_scale, 1.0), "Tier 4 desktop must use 1.0 native scale")

func _test_settings_persistence() -> void:
	var dpm := DevicePerformanceManager.new()
	dpm.detected_tier = DevicePerformanceManager.DeviceTier.TIER_1_BUDGET_MOBILE
	dpm.active_tier = DevicePerformanceManager.DeviceTier.TIER_1_BUDGET_MOBILE
	var profile := DevicePerformanceManager.get_profile_for_tier(dpm.active_tier, {"screen_refresh_rate": 60.0})

	var err := dpm.save_settings(profile, false, TEST_SETTINGS_PATH)
	_check(err == OK, "Saving settings to test path must succeed")
	_check(FileAccess.file_exists(TEST_SETTINGS_PATH), "Settings file must exist on disk")

	var loaded := dpm.load_settings(TEST_SETTINGS_PATH)
	_check(loaded.has("device_profile"), "Loaded settings must contain device_profile section")
	_check(loaded.has("performance"), "Loaded settings must contain performance section")
	_check(int(loaded.device_profile.detected_tier) == 1, "Persisted detected_tier must match")
	_check(int(loaded.performance.target_fps) == 30, "Persisted target_fps must match")
	_check(is_equal_approx(float(loaded.performance.scaling_3d_scale), 0.65), "Persisted scaling_3d_scale must match")
	_check(bool(loaded.performance.shadow_enabled) == false, "Persisted shadow_enabled must match")

	# Test manual override persistence
	dpm.override_tier(DevicePerformanceManager.DeviceTier.TIER_3_FLAGSHIP_KILLER, null)
	dpm.save_settings(dpm.active_profile, true, TEST_SETTINGS_PATH)
	var loaded_override := dpm.load_settings(TEST_SETTINGS_PATH)
	_check(bool(loaded_override.device_profile.manual_override) == true, "Manual override flag must be true")
	_check(int(loaded_override.device_profile.selected_tier) == 3, "Selected tier must be 3 after manual override")
	dpm.free()

func _test_apply_to_nodes() -> void:
	var dummy_game := Node3D.new()
	dummy_game.name = "DummyGame"
	root.add_child(dummy_game)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	dummy_game.add_child(sun)

	var dpm := DevicePerformanceManager.new()
	dummy_game.add_child(dpm)

	# Apply Tier 1 (Budget Mobile)
	var p1 := DevicePerformanceManager.get_profile_for_tier(DevicePerformanceManager.DeviceTier.TIER_1_BUDGET_MOBILE, {})
	dpm.apply_profile(dummy_game, p1)
	_check(Engine.max_fps == 30, "Applied Engine.max_fps must be 30 for Tier 1")
	_check(is_equal_approx(root.scaling_3d_scale, 0.65), "Applied root scaling_3d_scale must be 0.65 for Tier 1")
	_check(not sun.shadow_enabled, "Applied DirectionalLight3D shadow must be disabled for Tier 1")

	# Apply Tier 2 (Mid-Range Baseline)
	var p2 := DevicePerformanceManager.get_profile_for_tier(DevicePerformanceManager.DeviceTier.TIER_2_MID_RANGE, {})
	dpm.apply_profile(dummy_game, p2)
	_check(Engine.max_fps == 60, "Applied Engine.max_fps must be 60 for Tier 2")
	_check(is_equal_approx(root.scaling_3d_scale, 0.80), "Applied root scaling_3d_scale must be 0.80 for Tier 2")
	_check(sun.shadow_enabled, "Applied DirectionalLight3D shadow must be enabled for Tier 2")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "Applied DirectionalLight3D must use SHADOW_ORTHOGONAL for Tier 2")
	_check(is_equal_approx(sun.directional_shadow_max_distance, 35.0), "Applied DirectionalLight3D range must be 35 meters for Tier 2")

	dummy_game.queue_free()
