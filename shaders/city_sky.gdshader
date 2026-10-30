shader_type sky;
uniform float daylight = 1.0;
uniform float storminess = 0.0;
uniform float clock_hour = 16.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void sky() {
	float up = max(EYEDIR.y,0.0);
	vec3 horizon = mix(vec3(0.045,0.07,0.13),vec3(0.68,0.80,0.87),daylight);
	vec3 zenith = mix(vec3(0.009,0.016,0.05),vec3(0.12,0.38,0.68),daylight);
	vec3 color = mix(horizon,zenith,sqrt(up));
	float sunset = exp(-pow((clock_hour-18.3)/1.2,2.0)) + exp(-pow((clock_hour-6.3)/1.0,2.0));
	color = mix(color,vec3(0.8,0.37,0.21),clamp(sunset*(1.0-up)*0.5,0.0,0.7));
	vec2 p = EYEDIR.xz / max(EYEDIR.y+0.15,0.15)*2.0 + vec2(TIME*0.008,0.0);
	float cloud = noise(p)*0.6 + noise(p*2.0)*0.3 + noise(p*4.0)*0.1;
	float cover = smoothstep(mix(0.58,0.28,storminess),0.8,cloud)*smoothstep(-0.02,0.18,EYEDIR.y);
	vec3 clouds = mix(vec3(0.09,0.11,0.17),vec3(0.96),daylight)*(1.0-storminess*0.5);
	color = mix(color,clouds,cover);
	float star = step(0.998,hash(floor(SKY_COORDS*vec2(900.0,450.0))));
	color += star*(1.0-daylight)*(1.0-cover)*smoothstep(0.0,0.2,EYEDIR.y)*0.6;
	if (LIGHT0_ENABLED) {
		float sun = smoothstep(0.9994,0.9998,dot(EYEDIR,LIGHT0_DIRECTION));
		color += vec3(1.0,0.8,0.5)*sun*daylight*(1.0-cover);
	}
	COLOR = color;
}
