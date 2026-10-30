shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// Original, texture-free weathering. World-space stains stay continuous across
// mesh sections; UV2 distinguishes covers (1), walls (2), and channel beds (3).
uniform float city_wetness = 0.0;
varying vec3 drain_position;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise2(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 blend = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(cell), hash2(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash2(cell + vec2(0.0, 1.0)), hash2(cell + vec2(1.0)), blend.x), blend.y);
}
void vertex() {
	drain_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = drain_position.xz;
	float stains = noise2(p * 1.9);
	float aggregate = noise2(p * 38.0);
	float pores = hash2(floor(p * 155.0));
	vec3 concrete = COLOR.rgb * mix(0.64, 0.99, stains);
	concrete *= mix(0.87, 1.05, aggregate);
	concrete = mix(concrete, vec3(0.25, 0.205, 0.145), smoothstep(0.49, 0.82, stains) * 0.34);
	concrete *= 1.0 - smoothstep(0.91, 0.99, pores) * 0.20;
	float roughness = 0.95;
	if (UV2.x > 1.5 && UV2.x < 2.5) {
		// UV.y is actual relative wall height, not a repeated horizontal strip.
		float waterline = 0.36 + (stains - 0.5) * 0.20;
		float damp = 1.0 - smoothstep(waterline, waterline + 0.34, UV.y);
		concrete = mix(concrete, vec3(0.10, 0.135, 0.080) * mix(0.75, 1.25, aggregate), damp * 0.68);
		roughness = mix(0.97, 0.73, damp);
	} else if (UV2.x > 2.5) {
		concrete = mix(concrete, vec3(0.17, 0.135, 0.080), 0.60);
	} else if (UV2.x > 0.5) {
		float slab_id = floor(UV.x / 1.25);
		float slab_u = fract(UV.x / 1.25);
		float seam = smoothstep(0.008, 0.025, slab_u);
		float edge_distance = min(UV.y, 1.0 - UV.y);
		float chipped = (1.0 - smoothstep(0.0, 0.045 + aggregate * 0.045, edge_distance)) * smoothstep(0.40, 0.69, aggregate);
		concrete *= mix(0.47, 1.0, seam) * (1.0 - chipped * 0.28);
		concrete *= mix(0.88, 1.06, hash2(vec2(slab_id, 5.7)));
		// Sparse irregular hairline cracks, rather than a crack on every slab.
		float fracture_step = UV.y * 7.0;
		float fracture = mix(hash2(vec2(floor(fracture_step), slab_id)), hash2(vec2(floor(fracture_step) + 1.0, slab_id)), fract(fracture_step));
		float crack_path = 0.24 + fracture * 0.22;
		float crack = (1.0 - smoothstep(0.001, 0.004, abs(slab_u - crack_path))) * step(0.73, hash2(vec2(slab_id, 8.0)));
		concrete *= 1.0 - crack * 0.32;
		float panel = mod(UV.x, 16.0);
		if (panel > 0.15 && panel < 0.85 && UV.y > 0.18 && UV.y < 0.82) {
			float bars = step(0.45, fract(UV.x * 16.0));
			vec3 iron = mix(vec3(0.18, 0.19, 0.17), vec3(0.28, 0.15, 0.075), smoothstep(0.46, 0.80, aggregate) * 0.72);
			concrete = mix(vec3(0.035, 0.045, 0.028), iron, bars);
		}
		vec2 lid = vec2((mod(UV.x + 8.0, 32.0) - 0.5) / 0.45, (UV.y - 0.5) / 0.40);
		float radius = length(lid);
		if (radius < 1.0) {
			float ribs = step(0.25, fract(UV.x * 30.0)) * step(0.25, fract(UV.y * 18.0));
			vec3 iron = mix(vec3(0.15, 0.17, 0.145), vec3(0.26, 0.15, 0.075), smoothstep(0.40, 0.78, aggregate) * 0.65);
			concrete = iron * mix(0.65, 1.05, ribs);
			concrete *= mix(0.7, 1.2, step(0.85, radius));
		}
	}
	concrete *= 1.0 - city_wetness * 0.20;
	roughness = mix(roughness, 0.62, city_wetness);
	ALBEDO = concrete;
	ROUGHNESS = roughness;
}
