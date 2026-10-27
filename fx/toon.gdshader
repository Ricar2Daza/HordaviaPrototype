// Shader toon mínimo (guía §3.7): bandas de luz + rim light + tinte por altura.
// Uso: ShaderMaterial con este shader; ajusta base_color y shade_color por entidad.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.85, 0.75, 0.6, 1.0);
uniform vec3 shade_color : source_color = vec3(0.30, 0.26, 0.42);
uniform vec4 height_color : source_color = vec4(0.76, 0.82, 0.88, 1.0);
uniform float height_start = 9999.0;
uniform float height_end = 10000.0;
uniform float height_amount = 0.0;
uniform float rim_strength = 0.35;
uniform float bands = 3.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = smoothstep(height_start, height_end, world_pos.y) * height_amount;
	ALBEDO = mix(base_color.rgb, height_color.rgb, clamp(h, 0.0, 1.0));
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float band = clamp(floor(ndl * bands) / max(bands - 1.0, 1.0), 0.0, 1.0);
	float shade = mix(1.0, max(dot(shade_color, ALBEDO), 0.35), 1.0 - band);
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * ALBEDO * band;
	float rim = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += rim * rim_strength * LIGHT_COLOR * ALBEDO;
}
