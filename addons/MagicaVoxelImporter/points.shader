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
uniform float show_normals : hint_range(0,1);
varying vec2 voxel_size;
uniform bool sitting;
uniform float waist = 20f;
uniform float displacement_ratio = 5f;

float sit(float f)
{
	if(f>waist)
	{
		return -f/displacement_ratio;
	}
	return 0f;
}

void vertex() {
	if (sitting)
	{
		VERTEX.z += sit(VERTEX.y);
	}
	const vec3 half_voxel = vec3(0.5);
	COLOR.rgb = mix( pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb* (1.0 / 12.92), lessThan(COLOR.rgb,vec3(0.04045)) );
	float max_screen_size = max(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y);
	POINT_SIZE=point_size;
	ROUGHNESS=roughness;
	UV=UV*uv1_scale.xy+uv1_offset.xy;
	vec4 screen_space = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 screen_space1 = MODELVIEW_MATRIX * vec4(VERTEX - half_voxel, 1.0);
	vec4 screen_space2 = MODELVIEW_MATRIX * vec4(VERTEX + half_voxel, 1.0);
	screen_space.xyz /= screen_space.w;
	screen_space1.xyz /= screen_space1.w;
	screen_space2.xyz /= screen_space2.w;
	float diag = distance(screen_space2.xyz, screen_space1.xyz);
	// x / sqrt(3) to find the length of each side of a cube
	// TODO: find the largest projection space distance to a neigbour instead of edge_boost
	float voxel_side_half = (diag / sqrt(3)) * 0.5;
	vec3 screen_voxel_half = vec3(voxel_side_half, voxel_side_half, 0.0);
	vec4 proj_space1 = PROJECTION_MATRIX * vec4(screen_space.xyz - screen_voxel_half, 1.0);
	vec4 proj_space2 = PROJECTION_MATRIX * vec4(screen_space.xyz + screen_voxel_half, 1.0);
	proj_space1.xyz /= proj_space1.w;
	proj_space2.xyz /= proj_space2.w;
	vec2 vp_half = VIEWPORT_SIZE * 0.5;
	proj_space1.xy *= vp_half;
	proj_space2.xy *= vp_half;
	voxel_size = vec2(abs(proj_space2.x - proj_space1.x), abs(proj_space2.y - proj_space1.y));
	// Perspective projection
	if (PROJECTION_MATRIX[3][3] == 0.0) {
		vec4 proj_space = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		proj_space.xyz /= proj_space.w;
		vec2 aspect = vec2(min(1.0, VIEWPORT_SIZE.x / VIEWPORT_SIZE.y), min(1.0, VIEWPORT_SIZE.y / VIEWPORT_SIZE.x));
		vec2 edge_boost = abs(proj_space.xy) * aspect * 0.75;
		// proj_space.z is an exponent approaching 1 with depth
		// Don't edge boost more than 0.5 depth because it gets crazy big
		edge_boost *= (1.0 - max(proj_space.z, 0.5));
		voxel_size += edge_boost * edge_boost * vp_half;
	}
	POINT_SIZE = max(voxel_size.x, voxel_size.y) + 1.0;

	if (show_normals > 0.0) {
		COLOR = mix(COLOR, vec4(NORMAL, 1.0), show_normals);
		if (length(NORMAL) == 0.0) {
			COLOR = vec4(1.0, 0, 1.0, 0);
		}
	}

}
void fragment() {
	vec2 base_uv = UV;
	ALBEDO = albedo.rgb * COLOR.rgb;
	float aspect_x = min(1.0, voxel_size.x / voxel_size.y * 0.5);
	float aspect_y = min(1.0, voxel_size.y / voxel_size.x * 0.5);
	vec2 edge = abs(POINT_COORD - 0.5) - (vec2(aspect_x, aspect_y));
	if (edge.x > 0.0 || edge.y > 0.0) {
		discard;
		//ALBEDO = vec3(0.0)
	}
	RIM = .05;
	RIM_TINT = 0.9;
	float metallic_tex = dot(texture(texture_metallic,base_uv),metallic_texture_channel);
	METALLIC = metallic_tex * metallic;
	float roughness_tex = dot(texture(texture_roughness,base_uv),roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;
	SPECULAR = specular;
}
