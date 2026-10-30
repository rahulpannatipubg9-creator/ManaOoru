shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform float city_night = 0.0;
uniform float city_wetness = 0.0;

// Ground of the whole district, textured from what really covers it: ESA WorldCover
// 10 m land cover (trees, scrub, grass, crops, built-up, bare, water) picks CC0
// ground textures per cell. Cell edges are warped by noise so boundaries look
// natural, and large-scale noise varies brightness so the tiling does not show.

const float LAYER_TOWN = 0.0;
const float LAYER_BARE = 1.0;
const float LAYER_GRASS = 2.0;
const float LAYER_WOODLAND = 3.0;
const float LAYER_FARM = 4.0;
const float LAYER_SCRUB = 5.0;
const float LAYER_RED_SOIL = 6.0;

uniform sampler2D landcover : filter_nearest, repeat_disable;
// Seamless value noise (0..1, roughly uniform) for warping cell edges and placing patches.
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray ground_arm : filter_linear_mipmap, repeat_enable;
// World XZ of the land-cover raster's north-west corner, and its width in metres.
uniform vec2 landcover_origin = vec2(-3120.0, -3120.0);
uniform float landcover_extent = 6240.0;
// Metres covered by one repeat of a ground texture.
uniform float detail_scale = 3.5;
uniform vec3 water_color : source_color = vec3(0.06, 0.12, 0.11);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Land-cover code (ESA classes 10..100) at a world point.
float cover_at(vec2 xz) {
	vec2 uv = (xz - landcover_origin) / landcover_extent;
	return floor(texture(landcover, uv).r * 255.0 + 0.5);
}

float noise_at(vec2 xz, float scale) {
	return texture(noise, xz / scale).r;
}

// Ground layer for a land-cover class.
float layer_for(float code, float patches) {
	if (code < 15.0) return LAYER_WOODLAND;
	if (code < 25.0) return LAYER_SCRUB;
	if (code < 35.0) return LAYER_GRASS;
	if (code < 45.0) return LAYER_FARM;
	if (code < 55.0) return LAYER_TOWN;
	if (code < 65.0) return LAYER_BARE;
	if (code > 85.0) return LAYER_GRASS;
	return LAYER_TOWN;
}

void surface(float layer, vec2 xz, out vec3 albedo, out vec3 normal_map, out vec3 arm) {
	vec3 near_uv = vec3(xz / detail_scale, layer);
	albedo = texture(ground_albedo, near_uv).rgb;
	if (layer == LAYER_TOWN) {
		// Town earth is trodden grey-brown, not the source texture's sandy orange.
		albedo = mix(albedo, vec3(dot(albedo, vec3(0.3, 0.59, 0.11))), 0.35) * 0.78;
	}
	normal_map = texture(ground_normal, near_uv).rgb;
	arm = texture(ground_arm, near_uv).rgb;
}


float city_rain_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float city_rain_noise(vec2 p) {
 vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
 return mix(mix(city_rain_hash(i),city_rain_hash(i+vec2(1,0)),f.x),mix(city_rain_hash(i+vec2(0,1)),city_rain_hash(i+vec2(1)),f.x),f.y);
}

void fragment() {
	vec2 xz = world_position.xz;
	// Warp where the 10 m cells are read so their square edges become ragged and natural.
	vec2 warp = vec2(noise_at(xz, 23.0), noise_at(xz.yx + 50.0, 23.0)) * 14.0 - 7.0;
	float code_a = cover_at(xz + warp);
	float code_b = cover_at(xz - warp * 0.6 + vec2(3.0, -2.0));
	float patches = noise_at(xz, 61.0);
	vec3 albedo;
	vec3 normal_map;
	vec3 arm;
	surface(layer_for(code_a, patches), xz, albedo, normal_map, arm);
	float other = layer_for(code_b, patches);
	if (other != layer_for(code_a, patches)) {
		vec3 albedo_b;
		vec3 normal_b;
		vec3 arm_b;
		surface(other, xz, albedo_b, normal_b, arm_b);
		albedo = mix(albedo, albedo_b, 0.45);
		normal_map = mix(normal_map, normal_b, 0.45);
		arm = mix(arm, arm_b, 0.45);
	}
	if (code_a > 45.0 && code_a < 55.0) {
		// Open ground in town: dusty earth with soft-edged patches of red soil and weeds.
		float red = smoothstep(0.64, 0.8, patches) * 0.85;
		float weeds = 1.0 - smoothstep(0.12, 0.3, patches);
		if (red > 0.0 || weeds > 0.0) {
			vec3 albedo_b;
			vec3 normal_b;
			vec3 arm_b;
			surface(red > 0.0 ? LAYER_RED_SOIL : LAYER_GRASS, xz, albedo_b, normal_b, arm_b);
			float weight = max(red, weeds * 0.8);
			albedo = mix(albedo, albedo_b, weight);
			normal_map = mix(normal_map, normal_b, weight);
			arm = mix(arm, arm_b, weight);
		}
	}
	// Large-scale brightness drift: worn paths, damp patches, sun-bleached soil.
	albedo *= mix(0.82, 1.12, noise_at(xz, 140.0));
	if (code_a < 15.0) {
		// Woodland seen from beyond where trees are drawn reads as a green canopy, not leaf litter.
		float far = smoothstep(500.0, 800.0, distance(world_position, CAMERA_POSITION_WORLD));
		albedo = mix(albedo, vec3(0.07, 0.11, 0.045) * mix(0.8, 1.2, patches), far);
	}
	float roughness = arm.g;
	float specular = 0.5;
	if (code_a > 75.0 && code_a < 85.0) {
		// Ponds and lakes: dark, glassy water with slow ripples.
		vec2 ripple_uv = xz / 9.0 + vec2(TIME * 0.02, TIME * 0.013);
		normal_map = mix(vec3(0.5, 0.5, 1.0), texture(ground_normal, vec3(ripple_uv, LAYER_BARE)).rgb, 0.25);
		albedo = water_color;
		roughness = 0.06;
		specular = 0.8;
		arm = vec3(1.0, roughness, 0.0);
	}

 float city_puddle = smoothstep(0.56, 0.78, city_rain_noise(xz * 0.16)) * city_wetness;
 albedo *= 1.0 - city_wetness * 0.25;
 albedo = mix(albedo, albedo * 0.65 + vec3(0.035, 0.055, 0.065), city_puddle);
 if (city_puddle > 0.1) {
  vec2 cell = fract(xz * 2.2) - 0.5;
  float ring = abs(length(cell) - fract(TIME * 0.85 + city_rain_hash(floor(xz * 2.2))) * 0.65);
  albedo += (1.0 - smoothstep(0.008, 0.025, ring)) * city_puddle * 0.022;
 }
 ALBEDO = albedo;
	NORMAL_MAP = normal_map;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = mix(roughness, 0.18, city_puddle);
	SPECULAR = specular;
}
