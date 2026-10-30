shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform float city_night = 0.0;
uniform float city_wetness = 0.0;

// One material for every building, so each chunk still renders in one draw call.
// Walls use real CC0 surface textures (painted plaster, peeling paint, exposed
// brick, bare concrete, rolling shutters) from texture arrays, tinted by the
// building's paint, weathered with rain streaks and rising damp. Windows with
// grilles and curtains, open shops with lit goods and closed shutters are laid out
// procedurally from wall-space UVs. Signboards carry real place names only.
//   COLOR.rgb  paint colour (sRGB)
//   COLOR.a    style code / 255: bit 0 = residential (else shops on the ground
//              floor), bits 1-2 = wall finish, bits 3-7 = per-building seed
//   UV         (metres along the wall, metres above the building's base)
//   UV2        (height of the roof slab above the base, surface kind)

const float KIND_FACADE = 0.0;
const float KIND_PLAIN = 1.0;
const float KIND_ROOF = 2.0;
const float KIND_LEDGE = 3.0;
const float KIND_APRON = 4.0;
const float KIND_SIGN = 5.0;
const float LAYER_PLASTER = 0.0;
const float LAYER_PEELING = 1.0;
const float LAYER_BRICK = 2.0;
const float LAYER_CONCRETE = 3.0;
const float LAYER_SHUTTER = 4.0;

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray arm_array : filter_linear_mipmap, repeat_enable;
// Real place names baked by tools/signboards/make_signboards.gd; sign quads carry
// their atlas UVs in UV and the page in UV2.x.
uniform sampler2DArray signboard_pages : source_color, filter_linear_mipmap_anisotropic;
uniform float floor_height = 3.0;
uniform float bay_width = 3.2;
// Metres covered by one repeat of each wall texture.
uniform float plaster_scale = 2.4;
uniform float brick_scale = 1.8;
uniform float shutter_scale = 1.4;

varying vec2 surface;
varying vec3 world_position;

void vertex() {
	surface = UV2;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 to_linear(vec3 srgb) {
	return mix(srgb / 12.92, pow((srgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, srgb));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float box(vec2 p, vec2 lo, vec2 hi) {
	return step(lo.x, p.x) * step(p.x, hi.x) * step(lo.y, p.y) * step(p.y, hi.y);
}

// Wall finish sample: paint tints plaster; peeling paint keeps its bare patches grey.
void wall(float finish, vec2 metres, vec3 paint, out vec3 albedo, out vec3 normal_map, out vec3 arm) {
	float scale = finish == 2.0 ? brick_scale : plaster_scale;
	vec3 uv = vec3(metres / scale, LAYER_PLASTER);
	if (finish == 1.0) {
		uv.z = LAYER_PEELING;
	} else if (finish == 2.0) {
		uv.z = LAYER_BRICK;
	} else if (finish == 3.0) {
		uv.z = LAYER_CONCRETE;
	}
	vec3 tex = texture(albedo_array, uv).rgb;
	normal_map = texture(normal_array, uv).rgb;
	arm = texture(arm_array, uv).rgb;
	float luminance = dot(tex, vec3(0.299, 0.587, 0.114));
	if (finish == 0.0) {
		// Keep paint response bounded: bright texels must not turn pastel walls white.
		albedo = paint * clamp(luminance / 0.46, 0.55, 1.3);
	} else if (finish == 1.0) {
		// The source paint is red; where it is saturated, swap in this building's paint.
		float painted = smoothstep(0.08, 0.2, max(tex.r, max(tex.g, tex.b)) - min(tex.r, min(tex.g, tex.b)));
		albedo = mix(vec3(luminance) * 1.1, paint * clamp(luminance / 0.2, 0.6, 1.3), painted);
	} else {
		albedo = tex;
	}
}

void fragment() {
	float code = floor(COLOR.a * 255.0 + 0.5);
	bool residential = mod(code, 2.0) > 0.5;
	float finish = mod(floor(code / 2.0), 4.0);
	float seed = floor(code / 8.0);
	// Stable building-level proportions break identical window/shutter grids.
	// Uses existing vertex style bits: no new material, texture or draw calls.
	float building_pick = hash(vec2(seed + 17.0, seed * 1.7));
	float local_bay_width = bay_width * mix(0.88, 1.12, building_pick);
	float window_half_width = mix(0.20, 0.28, hash(vec2(seed, 71.0)));
	float window_top = mix(0.72, 0.81, hash(vec2(seed, 113.0)));
	vec3 paint = to_linear(COLOR.rgb);
	float height = UV.y;
	vec3 albedo;
	vec3 normal_map;
	vec3 arm;
	float roughness_scale = 1.0;
	float metallic = 0.0;
	vec3 emission = vec3(0.0);

	if (surface.y > KIND_SIGN - 0.5) {
		albedo = texture(signboard_pages, vec3(UV, surface.x)).rgb;
		normal_map = vec3(0.5, 0.5, 1.0);
		arm = vec3(1.0, 0.5, 0.0);
		emission = albedo * city_night * 0.85;
	} else if (surface.y > KIND_ROOF - 0.5 && surface.y < KIND_ROOF + 0.5) {
		vec3 uv = vec3(world_position.xz / 3.0, LAYER_CONCRETE);
		albedo = texture(albedo_array, uv).rgb * 0.85;
		normal_map = texture(normal_array, uv).rgb;
		arm = texture(arm_array, uv).rgb;
		// Monsoon stains pool towards the middle of flat roofs.
		albedo *= mix(0.7, 1.0, texture(arm_array, vec3(world_position.xz / 17.0, LAYER_CONCRETE)).r);
	} else if (surface.y > KIND_APRON - 0.5) {
		// Concrete forecourt in front of shops, scuffed by footfall.
		vec3 uv = vec3(world_position.xz / 2.0 + world_position.y, LAYER_CONCRETE);
		albedo = texture(albedo_array, uv).rgb * 0.7;
		normal_map = texture(normal_array, uv).rgb;
		arm = texture(arm_array, uv).rgb;
		albedo *= mix(0.75, 1.0, texture(arm_array, vec3(world_position.xz / 5.0, LAYER_PEELING)).r);
	} else if (surface.y > KIND_LEDGE - 0.5) {
		// Chajja sunshades and shop awnings: painted concrete slabs.
		wall(0.0, UV, mix(paint, vec3(0.8), 0.35), albedo, normal_map, arm);
		albedo *= 0.92;
	} else {
		wall(finish, UV, paint, albedo, normal_map, arm);
		bool facade = surface.y < KIND_PLAIN - 0.5;
		// Rain streaks run down from the parapet and each sill; damp rises from the plinth.
		float streaks = texture(arm_array, vec3(UV.x / 3.1, height / 22.0, LAYER_CONCRETE)).r;
		float from_top = clamp((surface.x - height) / 2.5, 0.0, 1.0);
		albedo *= mix(0.6, 1.0, mix(streaks, 1.0, from_top * 0.5 + 0.15));
		albedo *= mix(0.62, 1.0, smoothstep(0.25, 1.1, height));
		if (height < 0.48) {
			// A restrained cement skirt meets the soil above the sunk building base.
			vec3 plinth = texture(albedo_array, vec3(UV / 2.0, LAYER_CONCRETE)).rgb * 0.55;
			albedo = plinth;
		} else if (facade && height < surface.x - 0.4) {
			vec2 cell = vec2(fract(UV.x / local_bay_width), fract(height / floor_height));
			float bay = floor(UV.x / local_bay_width);
			float storey = floor(height / floor_height);
			float pick = hash(vec2(bay + seed * 13.0, storey + seed));
			bool shop_floor = storey < 0.5 && !residential;
			if (shop_floor) {
				float shop_height = 2.35;
				float front = box(vec2(cell.x, height), vec2(0.035, 0.32), vec2(0.965, shop_height));
				if (front > 0.5) {
					if (pick < 0.32) {
						// Closed rolling shutter, painted grey, green or blue.
						vec3 suv = vec3(UV.x / shutter_scale, height / shutter_scale, LAYER_SHUTTER);
						vec3 tint = pick < 0.12 ? vec3(0.9) : (pick < 0.22 ? vec3(0.55, 0.75, 0.6) : vec3(0.55, 0.65, 0.85));
						albedo = texture(albedo_array, suv).rgb * tint;
						normal_map = texture(normal_array, suv).rgb;
						arm = texture(arm_array, suv).rgb;
						metallic = 0.35;
					} else {
						// Open shop: a counter in front, shelves of goods behind in a dim interior
						// under warm tube lights, shutter rolled up at the top.
						float shelf = fract((height - 1.05) / 0.38);
						vec2 item = vec2(floor(UV.x / 0.3), floor((height - 1.05) / 0.38));
						float h = hash(item + bay * 7.0);
						vec3 goods = mix(vec3(0.32, 0.1, 0.06), vec3(0.6, 0.48, 0.18), h);
						goods = mix(goods, vec3(0.12, 0.22, 0.38), step(0.75, hash(item * 1.7 + 3.0)));
						goods = mix(goods, vec3(0.5), step(0.88, hash(item * 2.3 + 1.0)));
						float gap = step(0.82, shelf) + step(0.9, fract(UV.x / 0.3));
						albedo = mix(goods * 0.45, vec3(0.035, 0.03, 0.025), clamp(gap, 0.0, 1.0));
						albedo *= mix(0.55, 1.0, smoothstep(1.0, 2.2, height));
						emission = albedo * 0.25 + vec3(0.12, 0.1, 0.06) * smoothstep(1.7, 2.3, height);
						if (height < 1.05) {
							// Shop counter, painted like the signboard trim.
							albedo = mix(paint * 0.7, vec3(0.25, 0.12, 0.06), step(0.5, pick));
							albedo *= mix(0.8, 1.0, step(0.98, height));
							emission = vec3(0.0);
						}
						if (height > shop_height - 0.22) {
							vec3 suv = vec3(UV.x / shutter_scale, height * 3.0 / shutter_scale, LAYER_SHUTTER);
							albedo = texture(albedo_array, suv).rgb * 0.8;
							emission = vec3(0.0);
						}
						normal_map = vec3(0.5, 0.5, 1.0);
						roughness_scale = 0.8;
					}
				} else if (height > 2.42 && height < 2.98) {
					// Fascia band over the shop fronts, where a real board goes if the shop is mapped.
					albedo *= 0.8;
				}
			} else {
				// Window: frame, glass, Indian security grille and sometimes a curtain.
				vec2 lo = vec2(0.5 - window_half_width, 0.28);
				vec2 hi = vec2(0.5 + window_half_width, window_top);
				float frame = box(cell, lo, hi);
				float glass = box(cell, lo + vec2(0.018, 0.022), hi - vec2(0.018, 0.022));
				float sill = box(cell, vec2(lo.x - 0.03, lo.y - 0.03), vec2(hi.x + 0.03, lo.y));
				if (sill > 0.5) {
					albedo = vec3(0.62, 0.6, 0.56);
				}
				if (frame > 0.5) {
					albedo = pick < 0.5 ? vec3(0.78, 0.77, 0.72) : vec3(0.16, 0.32, 0.22);
					normal_map = vec3(0.5, 0.5, 1.0);
				}
				if (glass > 0.5) {
					if (hash(vec2(bay, storey) + seed * 3.1) > 0.58) { emission = vec3(0.64, 0.40, 0.15) * city_night; }
					// No reflection probes, so fake the sky in the glass: stronger at grazing angles.
					float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
					albedo = mix(vec3(0.05, 0.065, 0.08), vec3(0.32, 0.42, 0.5), 0.35 + 0.65 * fresnel);
					if (hash(vec2(bay, storey) + seed) < 0.35) {
						// Curtain drawn behind the glass.
						albedo = mix(albedo, mix(vec3(0.5, 0.15, 0.12), vec3(0.75, 0.62, 0.35), pick), 0.55);
					}
					normal_map = vec3(0.5, 0.5, 1.0);
					arm = vec3(1.0, 0.12, 0.0);
					float bars = step(0.86, fract((cell.x - lo.x) * local_bay_width / 0.12));
					bars = max(bars, box(vec2(0.0, cell.y), vec2(0.0, 0.52), vec2(1.0, 0.535)));
					if (bars > 0.5 && (residential || storey < 1.5)) {
						albedo = vec3(0.05, 0.06, 0.05);
						arm = vec3(1.0, 0.5, 0.6);
					}
				}
				// Shade cast by the chajja over each window.
				albedo *= mix(1.0, 0.72, box(cell, vec2(lo.x - 0.08, hi.y), vec2(hi.x + 0.08, hi.y + 0.06)));
			}
		}
	}
	albedo *= 1.0 - city_wetness * 0.16;
	emission *= 1.0 + city_night * 0.55;
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = 1.0;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = clamp(arm.g * roughness_scale, 0.05, 1.0);
	METALLIC = max(metallic, arm.b);
	EMISSION = emission;
}
