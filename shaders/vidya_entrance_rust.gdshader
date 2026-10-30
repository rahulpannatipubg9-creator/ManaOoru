shader_type spatial;
varying vec3 local_point;
void vertex() { local_point = VERTEX; }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
	vec2 p = local_point.xy;
	float wear = hash(floor(p*39.0));
	float streak = hash(vec2(floor(p.x*61.0),0));
	ALBEDO = mix(vec3(0.25,0.085,0.035),vec3(0.54,0.29,0.11),wear);
	ALBEDO = mix(ALBEDO,vec3(0.52,0.48,0.36),step(0.83,wear)*0.75);
	ALBEDO *= mix(0.73,1.0,streak);
	ROUGHNESS = 0.96;
}
