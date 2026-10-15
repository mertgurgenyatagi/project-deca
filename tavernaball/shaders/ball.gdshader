shader_type spatial;
// Classic football panels on a sphere: a truncated icosahedron of 12 black
// pentagons and 20 white hexagons, with thin dark seams. Each point takes the
// panel its ray from the centre hits first, i.e. the largest dot(p, n) / d over
// the panel normals n at plane distances d (edge length 1).

uniform vec3 hexagon_color : source_color = vec3(0.92, 0.92, 0.9);
uniform vec3 pentagon_color : source_color = vec3(0.04, 0.04, 0.05);
uniform vec3 seam_color : source_color = vec3(0.25, 0.25, 0.25);
// Seam width, in panel-score units (about 0.0018 per mm on a size-5 ball).
uniform float seam_width = 0.0022;
uniform float roughness_value = 0.45;

const float PHI = 1.6180339887;
const float IPHI = 0.6180339887;
const float PENTAGON_DISTANCE = 2.3274;
const float HEXAGON_DISTANCE = 2.2673;

// Icosahedron vertices: the pentagon centres.
const vec3 PENTAGONS[12] = vec3[](
	vec3(0.0, 1.0, PHI), vec3(0.0, 1.0, -PHI), vec3(0.0, -1.0, PHI), vec3(0.0, -1.0, -PHI),
	vec3(1.0, PHI, 0.0), vec3(1.0, -PHI, 0.0), vec3(-1.0, PHI, 0.0), vec3(-1.0, -PHI, 0.0),
	vec3(PHI, 0.0, 1.0), vec3(PHI, 0.0, -1.0), vec3(-PHI, 0.0, 1.0), vec3(-PHI, 0.0, -1.0)
);

// Icosahedron face centres (the dual dodecahedron's vertices): the hexagon centres.
const vec3 HEXAGONS[20] = vec3[](
	vec3(1.0, 1.0, 1.0), vec3(1.0, 1.0, -1.0), vec3(1.0, -1.0, 1.0), vec3(1.0, -1.0, -1.0),
	vec3(-1.0, 1.0, 1.0), vec3(-1.0, 1.0, -1.0), vec3(-1.0, -1.0, 1.0), vec3(-1.0, -1.0, -1.0),
	vec3(0.0, PHI, IPHI), vec3(0.0, PHI, -IPHI), vec3(0.0, -PHI, IPHI), vec3(0.0, -PHI, -IPHI),
	vec3(IPHI, 0.0, PHI), vec3(IPHI, 0.0, -PHI), vec3(-IPHI, 0.0, PHI), vec3(-IPHI, 0.0, -PHI),
	vec3(PHI, IPHI, 0.0), vec3(PHI, -IPHI, 0.0), vec3(-PHI, IPHI, 0.0), vec3(-PHI, -IPHI, 0.0)
);

varying vec3 object_direction;

void vertex() {
	object_direction = VERTEX;
}

void fragment() {
	vec3 p = normalize(object_direction);
	float best = -1.0;
	float second = -1.0;
	bool pentagon = false;
	for (int i = 0; i < 12; i++) {
		float s = dot(p, normalize(PENTAGONS[i])) / PENTAGON_DISTANCE;
		if (s > best) {
			second = best;
			best = s;
			pentagon = true;
		} else if (s > second) {
			second = s;
		}
	}
	for (int i = 0; i < 20; i++) {
		float s = dot(p, normalize(HEXAGONS[i])) / HEXAGON_DISTANCE;
		if (s > best) {
			second = best;
			best = s;
			pentagon = false;
		} else if (s > second) {
			second = s;
		}
	}
	vec3 color = pentagon ? pentagon_color : hexagon_color;
	float seam = 1.0 - smoothstep(seam_width * 0.5, seam_width, best - second);
	ALBEDO = mix(color, seam_color, seam);
	ROUGHNESS = roughness_value;
}
