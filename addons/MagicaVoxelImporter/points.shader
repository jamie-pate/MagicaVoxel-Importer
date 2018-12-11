shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;
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


void vertex() {
	COLOR.rgb = mix( pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb* (1.0 / 12.92), lessThan(COLOR.rgb,vec3(0.04045)) );
	POINT_SIZE=point_size * float(screen_size) * 0.001;
	ROUGHNESS=roughness;
	UV=UV*uv1_scale.xy+uv1_offset.xy;

	// NOTE: not sure why, but doubling the normal fixes lighting
	NORMAL = NORMAL * 2.0;
	if (PROJECTION_MATRIX[3][3] != 0.0) {
		float h = abs(1.0 / (2.0 * PROJECTION_MATRIX[1][1]));
		float sc = (h * 2.0); //consistent with Y-fov
		POINT_SIZE = POINT_SIZE * 1.0/sc; // untested!
	} else {
		vec4 screen_space = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		vec2 ascreen_space = abs(screen_space.xy);
		float sc = -screen_space.z;
		// increase point size with nearness to camera
		// also increase point size as we approach the edges of the screen to compensate for distortion.
		// TODO: generate some sort of sub-voxel 'antialiasing' to handle this?
		POINT_SIZE = POINT_SIZE * 1.0/sc * (max(ascreen_space.x, ascreen_space.y) * 1.25 + 1.0);
	}
}

void fragment() {
	vec2 base_uv = UV;
	ALBEDO = NORMAL;
	ALBEDO = albedo.rgb * COLOR.rgb; //albedo.rgb * albedo_tex.rgb;
	RIM = .05;
	RIM_TINT = 0.9;
	float metallic_tex = dot(texture(texture_metallic,base_uv),metallic_texture_channel);
	METALLIC = metallic_tex * metallic;
	float roughness_tex = dot(texture(texture_roughness,base_uv),roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;
	SPECULAR = specular;
}
