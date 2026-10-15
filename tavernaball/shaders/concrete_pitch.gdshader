shader_type spatial;
// Concrete floor with painted pitch markings. Markings are drawn analytically
// in the mesh's local XZ plane (origin = centre spot, units = meters), so lines
// stay crisp and anti-aliased at any distance.

group_uniforms concrete;
uniform vec3 concrete_color : source_color = vec3(0.21, 0.21, 0.22);
uniform float concrete_roughness : hint_range(0.0, 1.0) = 0.92;
uniform sampler2D concrete_noise : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Texture repeats per meter for large stains and for fine aggregate.
uniform float stain_scale = 0.04;
uniform float grain_scale = 0.6;
uniform float stain_strength : hint_range(0.0, 1.0) = 0.35;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.2;
uniform float normal_strength : hint_range(0.0, 4.0) = 0.8;
// Expansion joints between poured slabs (slab_size 0 = no joints).
uniform float slab_size = 4.5;
uniform float joint_width = 0.015;
uniform float joint_darkness : hint_range(0.0, 1.0) = 0.45;

group_uniforms markings;
uniform bool show_markings = true;
uniform vec3 line_color : source_color = vec3(0.86, 0.86, 0.83);
uniform float line_roughness : hint_range(0.0, 1.0) = 0.8;
// How much the paint is worn through to the concrete.
uniform float line_wear : hint_range(0.0, 1.0) = 0.25;
uniform vec2 pitch_size = vec2(36.5, 27.5);
uniform float line_width = 0.08;
uniform float center_circle_radius = 2.75;
// Penalty area: semicircle centred on the middle of each goal line.
uniform float penalty_area_radius = 6.0;
uniform float penalty_spot_distance = 6.0;
uniform float spot_radius = 0.12;

varying vec2 local_xz;

void vertex() {
	local_xz = VERTEX.xz;
}

// Anti-aliased coverage of a band of half-width `half_width` around dist == 0.
// Bands thinner than a pixel are widened and faded so they never vanish.
float band(float dist, float half_width) {
	float aa = max(fwidth(dist), 1e-5);
	float w = max(half_width, aa * 0.5);
	return clamp((w - dist) / aa + 0.5, 0.0, 1.0) * (half_width / w);
}

float markings(vec2 q) {
	vec2 h = pitch_size * 0.5;
	float hw = line_width * 0.5;

	// Touchlines and goal lines: rectangle outline, lines inside the pitch.
	vec2 d = abs(q) - (h - hw);
	float rect = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	float m = band(abs(rect), hw);

	m = max(m, band(abs(q.x), hw));  // Halfway line.

	// Centre circle (outer edge at the radius) and centre spot.
	float r = length(q);
	m = max(m, band(abs(r - (center_circle_radius - hw)), hw));
	m = max(m, band(r, spot_radius));

	for (int i = 0; i < 2; i++) {
		float side = i == 0 ? -1.0 : 1.0;
		float rp = length(q - vec2(side * h.x, 0.0));
		m = max(m, band(abs(rp - (penalty_area_radius - hw)), hw));
		vec2 spot = vec2(side * (h.x - penalty_spot_distance), 0.0);
		m = max(m, band(length(q - spot), spot_radius));
	}

	return m * step(abs(q.x), h.x) * step(abs(q.y), h.y);
}

void fragment() {
	vec2 q = local_xz;
	float stain = texture(concrete_noise, q * stain_scale).r;
	float grain = texture(concrete_noise, q * grain_scale + vec2(0.37, 0.71)).r;

	vec3 concrete = concrete_color
			* (1.0 + (stain - 0.5) * 2.0 * stain_strength)
			* (1.0 + (grain - 0.5) * 2.0 * grain_strength);

	if (slab_size > 0.0) {
		vec2 g = abs(fract(q / slab_size + 0.5) - 0.5) * slab_size;
		concrete *= 1.0 - band(min(g.x, g.y), joint_width * 0.5) * joint_darkness;
	}

	float paint = show_markings ? markings(q) : 0.0;
	paint *= 1.0 - line_wear * smoothstep(0.35, 0.75, 1.0 - grain);

	ALBEDO = mix(concrete, line_color, paint);
	ROUGHNESS = mix(concrete_roughness, line_roughness, paint);
	SPECULAR = 0.35;
	NORMAL_MAP = texture(concrete_normal, q * grain_scale).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - 0.6 * paint);
}
