shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;// vertex_lighting;//, unshaded;
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
	if (PROJECTION_MATRIX[3][3] != 0.0) {
		float h = abs(1.0 / (2.0 * PROJECTION_MATRIX[1][1]));
		float sc = (h * 2.0); //consistent with Y-fov
		MODELVIEW_MATRIX[0]*=sc;
		MODELVIEW_MATRIX[1]*=sc;
		MODELVIEW_MATRIX[2]*=sc;
	} else {
		float sc = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
		POINT_SIZE = POINT_SIZE * 1.0/sc;
	}
}

void fragment() {
	vec2 base_uv = UV;
	//vec4 albedo_tex = texture(texture_albedo,POINT_COORD);
	//albedo_tex *= COLOR;
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
