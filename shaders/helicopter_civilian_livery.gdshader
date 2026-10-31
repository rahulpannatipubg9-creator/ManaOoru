shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Civilian VIP livery: Godavarikhani / Ramagundam executive charter
// Ivory upper fuselage, muted gold cheatline, deep forest green belly/skids, tinted glass

const vec3 COLOR_IVORY = vec3(0.961, 0.949, 0.922);        // #F5F2EB
const vec3 COLOR_GOLD = vec3(0.769, 0.659, 0.408);         // #C4A868
const vec3 COLOR_FOREST_GREEN = vec3(0.106, 0.220, 0.149); // #1B3826
const vec3 COLOR_TINTED_GLASS = vec3(0.06, 0.09, 0.11);    // High-gloss tinted cabin glass

varying vec3 v_world_pos;
varying vec3 v_local_pos;
varying vec3 v_normal;

void vertex() {
	v_local_pos = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Fuselage height in vehicle coordinates:
	// Ground at Y ~ 0.1, skids Y ~ 0.2 - 0.7, belly Y ~ 0.8 - 1.35,
	// Gold stripe Y ~ 1.35 - 1.48, Ivory upper Y ~ 1.48 - 2.8.
	float y = v_world_pos.y;
	
	// Determine base paint color based on height zones with smooth transition
	vec3 base_color;
	float roughness = 0.25;
	float metallic = 0.15;
	
	if (y < 1.35) {
		// Deep forest-green belly and landing skids
		base_color = COLOR_FOREST_GREEN;
		roughness = 0.35;
		metallic = 0.10;
	} else if (y < 1.48) {
		// Thin muted-gold cheatline
		base_color = COLOR_GOLD;
		roughness = 0.30;
		metallic = 0.65;
	} else {
		// Warm ivory upper fuselage
		base_color = COLOR_IVORY;
		roughness = 0.22;
		metallic = 0.12;
	}
	
	// Forward cabin windows:
	// In the cabin nose area (world Z < -1.0, Y between 1.35 and 2.15, facing forward or outward)
	bool is_cockpit_zone = (v_world_pos.z < -1.15 && v_world_pos.z > -3.3 && y > 1.38 && y < 2.15);
	bool faces_glass = (v_normal.z < -0.15 || abs(v_normal.x) > 0.45);
	
	if (is_cockpit_zone && faces_glass && abs(v_local_pos.x) < 0.95) {
		// Glossy tinted cabin window
		ALBEDO = COLOR_TINTED_GLASS;
		ROUGHNESS = 0.04;
		METALLIC = 0.25;
		SPECULAR = 0.85;
	} else {
		ALBEDO = base_color;
		ROUGHNESS = roughness;
		METALLIC = metallic;
		SPECULAR = 0.5;
	}
}
