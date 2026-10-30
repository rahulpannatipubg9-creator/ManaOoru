shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Real trees drawn as four crossed cards, each showing the CC0 jacaranda model photographed
// from its own angle (atlas of four 512 px views). Cut out with alpha scissor so they
// sort and cast shadows like solid geometry. Every instance gets a slight colour shift
// from INSTANCE_CUSTOM so a stand of trees is not one repeated tint.

uniform sampler2D impostor : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut = 0.45;
uniform float saturation = 1.25;
// Crown centre height as a share of the card height, for rounded crown lighting.
uniform float crown_center = 0.52;
// Card size in model units (the impostor frame, metres).
uniform float card_size = 24.91;

varying vec3 local_position;
varying vec3 tint;

void vertex() {
	local_position = VERTEX;
	tint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec4 sample = texture(impostor, UV);
	if (sample.a < alpha_cut) {
		discard;
	}
	vec3 color = sample.rgb;
	float grey = dot(color, vec3(0.3, 0.59, 0.11));
	color = mix(vec3(grey), color, saturation) * tint;
	ALBEDO = color;
	ROUGHNESS = 0.85;
	// Light the crown as a rounded volume rather than flat cards.
	vec3 p = local_position / card_size;
	vec3 round_normal = normalize(vec3(p.x, (p.y - crown_center) * 1.2 + 0.45, p.z));
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(round_normal, 0.0)).xyz);
}
