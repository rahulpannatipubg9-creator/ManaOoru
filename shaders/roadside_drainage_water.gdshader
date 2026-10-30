shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
// Opaque, shallow, murky water with stationary silt at the banks. No extra pass.
uniform float flow_speed = 0.10;
uniform float rain_amount = 0.0;
void vertex() { VERTEX.y += rain_amount * 0.028; }
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
void fragment() {
	float bank = min(UV.y, 1.0 - UV.y);
	float settled = noise2(vec2(UV.x * 2.3, UV.y * 9.0));
	float silt = 1.0 - smoothstep(0.025, 0.10 + settled * 0.20, bank);
	float drift = noise2(vec2(UV.x * 0.8 - TIME * 0.025, UV.y * 4.0));
	float wave = sin(UV.x * 16.0 - TIME * (flow_speed + rain_amount * 0.18) * 16.0 + sin(UV.y * 17.0));
	vec3 water = mix(vec3(0.065, 0.085, 0.048), vec3(0.12, 0.15, 0.078), drift);
	vec3 sediment = mix(vec3(0.15, 0.12, 0.067), vec3(0.22, 0.175, 0.095), settled);
	ALBEDO = mix(water + wave * (0.006 + rain_amount * 0.012), sediment, silt * 0.83);
	ROUGHNESS = mix(0.48, 0.95, silt);
	SPECULAR = mix(0.30, 0.06, silt);
}
