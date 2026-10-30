shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, skip_vertex_transform;

// Distant trees: one card per tree that turns to face the camera around its trunk and
// shows whichever of the four impostor views (see tree_impostor.gdshader) matches the
// direction it is seen from. A quarter of the overdraw of the four crossed cards.

uniform sampler2D impostor : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.45;
uniform float saturation = 1.25;

varying vec3 tint;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 camera = INV_VIEW_MATRIX[3].xyz;
	vec3 to_camera = camera - center;
	to_camera.y = 0.0;
	to_camera = normalize(to_camera + vec3(0.0001, 0.0, 0.0));
	float across_scale = length(MODEL_MATRIX[0].xyz);
	float up_scale = length(MODEL_MATRIX[1].xyz);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_camera));
	vec3 world = center + right * VERTEX.x * across_scale + vec3(0.0, VERTEX.y * up_scale, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// Mostly upward, so distant crowns catch the sun like the near ones instead of going dark.
	NORMAL = normalize((VIEW_MATRIX * vec4(to_camera * 0.35 + vec3(0.0, 1.0, 0.0), 0.0)).xyz);
	// Which photographed view faces the camera, measured in the tree's own yaw.
	vec3 forward = normalize(MODEL_MATRIX[2].xyz);
	vec3 side = normalize(MODEL_MATRIX[0].xyz);
	float angle = atan(dot(to_camera, side), dot(to_camera, forward));
	float view = mod(floor(angle / (PI * 0.25) + 0.5), 4.0);
	UV.x = (view + UV.x) * 0.25;
	tint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec4 sample = texture(impostor, UV);
	if (sample.a < alpha_cut) {
		discard;
	}
	vec3 color = sample.rgb;
	float grey = dot(color, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(vec3(grey), color, saturation) * tint;
	ROUGHNESS = 0.9;
}
