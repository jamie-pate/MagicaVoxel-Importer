shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx, unshaded;
uniform vec4 albedo : hint_color;
uniform sampler2D texture_albedo : hint_albedo;
uniform float specular;
uniform float metallic;
uniform float roughness : hint_range(0,1);
uniform float point_size : hint_range(0,128);
uniform sampler2D texture_metallic : hint_white;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_white;
uniform vec4 roughness_texture_channel;
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;
uniform int screen_size;
varying float x_squash;
varying float y_squash;


void vertex() {
	COLOR.rgb = mix( pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb* (1.0 / 12.92), lessThan(COLOR.rgb,vec3(0.04045)) );
	POINT_SIZE=point_size * float(screen_size) * 0.001;
	ROUGHNESS=roughness;
	UV=UV*uv1_scale.xy+uv1_offset.xy;

	if (PROJECTION_MATRIX[3][3] != 0.0) {
		float h = abs(1.0 / (2.0 * PROJECTION_MATRIX[1][1]));
		float sc = (h * 2.0); //consistent with Y-fov
		POINT_SIZE = POINT_SIZE * 1.0/sc; // untested!
	} else {
		vec4 screen_space = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float sc = -screen_space.z;
		vec4 proj_space = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		PROJECTION_MATRIX *= mat4(1.0);
		vec2 ascreen_space = abs(proj_space.xy);
		float ss_max = max(ascreen_space.x, ascreen_space.y);
		// increase point size with nearness to camera
		// also increase point size as we approach the edges of the screen to compensate for distortion.
		// TODO: generate some sort of sub-voxel 'antialiasing' to handle this?
		//float EDGE_GROW = 0.5;
		float EDGE_GROW = 0.0;
		POINT_SIZE = POINT_SIZE * 1.0/sc * (ss_max * EDGE_GROW + 1.0);
		// HAVE To get Z in here somehow
		if (ascreen_space.x > ascreen_space.y) {
			x_squash = ascreen_space.x;
			y_squash = 0.0;
		} else {
			y_squash = ascreen_space.y;
			x_squash = 0.0;
		}
	}
}

void fragment() {
	vec2 base_uv = UV;
	ALBEDO = albedo.rgb * COLOR.rgb;
	vec2 PARABLOID = vec2(
		0.9, // roundness, 1.0 = round, 0.0 = square
		0.15 // straight edge length 1.0 = straightest, 0.1 = almost none
	);
	float EDGE_SQUASH = 1.5;
	vec2 edge = 1.0 - abs(POINT_COORD - vec2(0.5)) * 2.0;
	if (x_squash > 0.0) {
		edge.x *= x_squash;
		ALBEDO.r = mod(FRAGCOORD.x, 50.0) + VIEWPORT_SIZE.x;
		ALBEDO.b = min(0.5, mod(x_squash, 0.2) * 10.0);
	}
	if (y_squash > 0.0) {
		edge.y *= y_squash;
		ALBEDO.g = mod(FRAGCOORD.y, 50.0) + VIEWPORT_SIZE.y;
		ALBEDO.b = min(0.5, mod(y_squash, 0.2) * 10.0);
	}
	edge = 1.0 - (pow(edge.yx, vec2(PARABLOID.x)) + (edge.xy * PARABLOID.y));

	
	//ALBEDO.rg = edge.xy;
	float cutoff = 0.9;
	if (edge.x > cutoff || edge.y > cutoff) {
		discard;
	}
	//ALBEDO = vec3(.x, .y, 0);
	RIM = .05;
	RIM_TINT = 0.9;
	float metallic_tex = dot(texture(texture_metallic,base_uv),metallic_texture_channel);
	METALLIC = metallic_tex * metallic;
	float roughness_tex = dot(texture(texture_roughness,base_uv),roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;
	SPECULAR = specular;
}
