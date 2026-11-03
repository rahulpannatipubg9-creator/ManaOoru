shader_type canvas_item;

// Dusk over Godavarikhani, drawn with no art: a low marigold sun behind the flat-topped
// coal dumps, the town's rooflines, and one pit headframe. Everything below the sky is
// silhouette, so it stays quiet behind the menu.

uniform vec3 ink : source_color = vec3(0.051, 0.078, 0.098);
uniform vec3 marigold : source_color = vec3(0.961, 0.702, 0.208);
uniform float aspect = 1.778;
// Horizontal place of the sun and headframe, in screen widths.
uniform float focus = 0.73;

float hash(float value) {
	return fract(sin(value * 127.1) * 43758.5453);
}

float noise(float value) {
	float cell = floor(value);
	float blend = fract(value);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(hash(cell), hash(cell + 1.0), blend);
}

// Flat-topped ridge: the overburden dumps around the open-cast mines.
float dumps(float x) {
	float mound = noise(x * 1.7 + 4.0) * 0.6 + noise(x * 4.3) * 0.25;
	return smoothstep(0.28, 0.62, mound) * 0.105;
}

// Stepped rooflines, widths and heights picked per block.
float roofs(float x) {
	float block = floor(x * 19.0);
	float height = 0.035 + hash(block) * 0.05;
	if (hash(block + 40.0) > 0.86) {
		height += 0.045;
	}
	return height;
}

float box(vec2 point, vec2 centre, vec2 half_size) {
	vec2 delta = abs(point - centre) - half_size;
	return step(max(delta.x, delta.y), 0.0);
}

// The leaning legs, deck and winding wheel of a shaft headframe.
float headframe(vec2 point) {
	vec2 local = point;
	float width = 0.0016;
	float shape = 0.0;
	for (int side = 0; side < 2; side++) {
		float sign_x = side == 0 ? -1.0 : 1.0;
		float leg = abs(local.x - sign_x * (0.052 - local.y * 0.26));
		shape = max(shape, step(leg, width * 1.6) * step(0.0, local.y) * step(local.y, 0.19));
	}
	float back_stay = abs(local.x + local.y * 0.62 - 0.125);
	shape = max(shape, step(back_stay, width * 1.5) * step(0.0, local.y) * step(local.y, 0.19));
	for (int rung = 1; rung < 5; rung++) {
		float rung_y = float(rung) * 0.038;
		shape = max(shape, box(local, vec2(0.0, rung_y), vec2(0.052 - rung_y * 0.26, width)));
	}
	shape = max(shape, box(local, vec2(0.0, 0.192), vec2(0.03, 0.0032)));
	vec2 wheel = local - vec2(0.0, 0.222);
	float ring = abs(length(wheel) - 0.028);
	shape = max(shape, step(ring, 0.0028));
	shape = max(shape, step(abs(wheel.x), 0.0014) * step(abs(wheel.y), 0.028));
	shape = max(shape, step(abs(wheel.y), 0.0014) * step(abs(wheel.x), 0.028));
	return shape;
}

void fragment() {
	float x = UV.x * aspect;
	float height = 1.0 - UV.y;
	vec2 sun_at = vec2(focus * aspect, 0.235);
	vec2 point = vec2(x, height);
	float sun_distance = length(point - sun_at);

	// Sky: ink overhead, burning down toward the sun, dark again away from it.
	float reach = exp(-sun_distance * 2.1);
	vec3 sky = mix(ink, vec3(0.20, 0.13, 0.13), smoothstep(0.85, 0.25, height));
	sky = mix(sky, vec3(0.74, 0.33, 0.10), reach * reach * 1.25);
	sky += marigold * exp(-sun_distance * 7.0) * 0.45;
	// Thin coal haze across the horizon.
	float haze = noise(x * 2.2 + TIME * 0.012) * noise(height * 26.0 + x * 1.3 - TIME * 0.02);
	sky += vec3(0.16, 0.08, 0.04) * haze * smoothstep(0.55, 0.18, height) * (0.25 + reach);

	vec3 color = sky;
	float sun = smoothstep(0.17, 0.168, sun_distance);
	color = mix(color, mix(marigold, vec3(1.0, 0.86, 0.52), smoothstep(0.1, 0.33, height)), sun);

	float frame_base = 0.13;
	vec2 frame_at = point - vec2(sun_at.x + 0.015, frame_base);
	float far_line = 0.135 + dumps(x + 0.9);
	color = mix(color, mix(vec3(0.30, 0.15, 0.10), ink, 0.45), step(height, far_line));
	color = mix(color, vec3(0.055, 0.045, 0.05), headframe(frame_at));

	float town_line = 0.075 + roofs(x) + noise(x * 3.0) * 0.03;
	color = mix(color, ink * 0.72, step(height, town_line));

	// Keep the left of the frame dark so the title and menu read.
	color = mix(color, ink * 0.8, smoothstep(0.62, 0.04, UV.x) * 0.55);
	COLOR = vec4(color, 1.0);
}
