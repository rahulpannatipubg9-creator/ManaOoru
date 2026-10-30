shader_type spatial;
render_mode diffuse_lambert;
varying vec3 wall_position;
void vertex() { wall_position = VERTEX; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}
void fragment() {
	vec2 p = wall_position.xy;
	float mottling = noise(p*5.0)*0.5 + noise(p*21.0)*0.3 + noise(p*87.0)*0.2;
	float rising_damp = (1.0-smoothstep(-0.8,-0.15,p.y)) * (0.4+noise(p*9.0)*0.6);
	float worn = smoothstep(0.42,0.68,noise(p*3.7));
	vec3 plaster = mix(vec3(0.56,0.54,0.45),vec3(0.35,0.34,0.29),worn*0.55);
	ALBEDO = plaster * mix(0.70,1.15,mottling) * (1.0-rising_damp*0.55);
	ROUGHNESS = 0.98;
}
