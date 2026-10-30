shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform float city_night = 0.0;
uniform float city_wetness = 0.0;

// Road-level ground: carriageways in real CC0 asphalt (cracked dark asphalt on main
// roads, worn brown asphalt on minor ones) with dusty edges, gravel-and-dirt
// shoulders, dirt paths and tracks, and parks, pitches, quarries and water drawn
// with the same textures as the surrounding ground.
//   UV2.x  surface kind (see KIND_*); UV.x across a carriageway (-1..1) or a shoulder
//          (0 at the asphalt edge, 1 outside); COLOR is the old flat colour, used as a tint.

const float KIND_AREA = 0.0;
const float KIND_MAJOR = 1.0;
const float KIND_MINOR = 2.0;
const float KIND_DIRT = 3.0;
const float KIND_SHOULDER = 4.0;
const float KIND_PARK = 10.0;
const float KIND_PITCH = 11.0;
const float KIND_WATER = 13.0;
const float KIND_QUARRY = 14.0;
// Layers of the ground texture arrays (see tools/make_ground_textures.py).
const float GROUND_TOWN = 0.0;
const float GROUND_BARE = 1.0;
const float GROUND_GRASS = 2.0;

uniform sampler2DArray road_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray road_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray road_arm : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_arm : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float asphalt_scale = 4.0;
uniform float ground_scale = 3.5;
uniform vec3 water_color : source_color = vec3(0.06, 0.12, 0.11);

varying vec3 world_position;
varying float kind;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	kind = UV2.x;
}

void ground(float layer, vec2 xz, out vec3 albedo, out vec3 normal_map, out vec3 arm) {
	vec3 uv = vec3(xz / ground_scale, layer);
	albedo = texture(ground_albedo, uv).rgb;
	normal_map = texture(ground_normal, uv).rgb;
	arm = texture(ground_arm, uv).rgb;
}


float city_rain_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float city_rain_noise(vec2 p) {
 vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
 return mix(mix(city_rain_hash(i),city_rain_hash(i+vec2(1,0)),f.x),mix(city_rain_hash(i+vec2(0,1)),city_rain_hash(i+vec2(1)),f.x),f.y);
}

void fragment() {
	vec2 xz = world_position.xz;
	float drift = texture(noise, xz / 90.0).r;
	vec3 albedo;
	vec3 normal_map;
	vec3 arm;
	float specular = 0.5;
	if (kind > KIND_MAJOR - 0.5 && kind < KIND_MINOR + 0.5) {
		float layer = kind < 1.5 ? 0.0 : 1.0;
		vec3 uv = vec3(xz / asphalt_scale, layer);
		albedo = texture(road_albedo, uv).rgb;
		normal_map = texture(road_normal, uv).rgb;
		arm = texture(road_arm, uv).rgb;
		// Patch repairs and sun-faded stretches.
		albedo *= mix(0.78, 1.18, drift);
		// Dust blown onto the outer half metre of the carriageway.
		float edge = smoothstep(0.78, 1.0, abs(UV.x));
		vec3 dust;
		vec3 dust_normal;
		vec3 dust_arm;
		ground(GROUND_TOWN, xz, dust, dust_normal, dust_arm);
		albedo = mix(albedo, dust * 0.8, edge * 0.7);
	} else if (kind > KIND_SHOULDER - 0.5 && kind < KIND_SHOULDER + 0.5) {
		// Gravel shoulder: dark and stony next to the asphalt, fading into the verge.
		vec3 gravel;
		vec3 gravel_normal;
		vec3 gravel_arm;
		ground(GROUND_BARE, xz, gravel, gravel_normal, gravel_arm);
		ground(GROUND_TOWN, xz, albedo, normal_map, arm);
		float out_share = clamp(UV.x, 0.0, 1.0);
		albedo = mix(gravel * 0.85, albedo * 0.9, out_share);
		normal_map = mix(gravel_normal, normal_map, out_share);
	} else if (kind > KIND_DIRT - 0.5 && kind < KIND_DIRT + 0.5) {
		ground(GROUND_TOWN, xz, albedo, normal_map, arm);
		albedo *= 0.8;
	} else if (kind > KIND_WATER - 0.5 && kind < KIND_WATER + 0.5) {
		vec2 ripple_uv = xz / 9.0 + vec2(TIME * 0.02, TIME * 0.013);
		normal_map = mix(vec3(0.5, 0.5, 1.0), texture(ground_normal, vec3(ripple_uv, GROUND_BARE)).rgb, 0.25);
		albedo = water_color;
		arm = vec3(1.0, 0.06, 0.0);
		specular = 0.8;
	} else if (kind > KIND_QUARRY - 0.5 && kind < KIND_QUARRY + 0.5) {
		ground(GROUND_BARE, xz, albedo, normal_map, arm);
		albedo *= 0.55;
	} else if (kind > KIND_PARK - 0.5) {
		// Parks, gardens, stadium turf and pitches: grass, greener on pitches.
		ground(GROUND_GRASS, xz, albedo, normal_map, arm);
		albedo *= kind > KIND_PITCH - 0.5 && kind < KIND_PITCH + 0.5 ? vec3(0.9, 1.15, 0.85) : vec3(1.0);
	} else {
		// Vertex colours are authored in sRGB (rail ballast and other flat pieces).
		vec3 srgb = COLOR.rgb;
		albedo = mix(srgb / 12.92, pow((srgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, srgb));
		normal_map = vec3(0.5, 0.5, 1.0);
		arm = vec3(1.0, 0.9, 0.0);
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
	ROUGHNESS = mix(arm.g, 0.14, city_puddle);
	SPECULAR = specular;
}
