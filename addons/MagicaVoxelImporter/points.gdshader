shader_type spatial;
render_mode blend_mix,depth_draw_opaque,diffuse_burley,specular_schlick_ggx, skip_vertex_transform;
uniform vec4 albedo : source_color;
uniform float specular;
uniform float metallic;
uniform float roughness : hint_range(0,1);
uniform sampler2D texture_metallic : hint_default_white;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_default_white;
uniform vec4 roughness_texture_channel;
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform float show_normals : hint_range(0, 1);
// This only works if the mesh was imported with "Copy Bones to UV"
uniform float show_bone_weights : hint_range(0, 1);
varying vec2 voxel_size;
uniform float root_scale = 1.0;
uniform bool fast;
uniform bool render_head = true;
// script is responsible for not setting render_head = false if these indexes aren't set
uniform uint neck_bone_index = 0;
uniform uint head_bone_index = 0;
uniform float phase_shift: hint_range(0, 1) = 0.0;
uniform bool super_black = false;
// increase lod bias to remove more voxels when closer to the camera
// 2.0 means when each voxel is only 2px we start rendering half the voxels
uniform float lod_bias = 2.0;
// worst case lod reduction
// 5.0 = at most discard 4/5 voxels on each axis.
// limiting this is somehow faster than allowing the whole mesh to be discarded.
uniform float lod_worst = 5.0;
// multiply a uint by this number to get a range from 0 .. 2.0
// #ifndef GLES3
const float MAX_UINT_INV_2 = 2.0 / float(~0u);
// #endif
const float PHASE_TRANSLATE = 0.01;
const float PHASE_SHRINK = 0.25;

#ifndef GLES2
uint pcg_hash(uint input) {
	// https://www.reedbeta.com/blog/hash-functions-for-gpu-rendering/
    uint state = input * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// Add amount of randomness to a value, plus or minus amount
float phase_shift_component(float seed, float value, float amount) {
	uint bits = floatBitsToUint(seed);
	bits = pcg_hash(bits);
	float r = float(bits) * MAX_UINT_INV_2;
	r -= 1.0;
	return value + r * amount;
}

vec3 phase_shift_vertex(vec3 value, float amount) {
	return vec3(
		phase_shift_component(value.x + value.z + amount + TIME, value.x, amount),
		phase_shift_component(value.y + value.x + amount + TIME, value.y, amount),
		phase_shift_component(value.z + value.y + amount + TIME, value.z, amount)
	);
}
#endif

void vertex() {
	float head_or_neck_bone = 0.0;
	for (int i = 0; i < 4; ++i) {
		if (BONE_INDICES[i] == neck_bone_index) {
			head_or_neck_bone += BONE_WEIGHTS[i];
		}
		if (BONE_INDICES[i] == head_bone_index) {
			head_or_neck_bone += BONE_WEIGHTS[i];
		}
	}
	if (!render_head && head_or_neck_bone > 0.0) {
		voxel_size = vec2(0.0);
	} else {
		// color correction?
		COLOR.rgb = mix( pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb,vec3(0.04045)) );
		float max_screen_size = max(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y);
		ROUGHNESS=roughness;
		vec4 bone_color = vec4(UV, UV2);
		UV=UV*uv1_scale.xy+uv1_offset.xy;
		vec3 half_voxel = vec3(0.5) * root_scale;
		bool ortho = PROJECTION_MATRIX[3][3] != 0.0;
		mat4 mvp = PROJECTION_MATRIX * MODELVIEW_MATRIX;
		vec3 nt_normal = NORMAL;
		// SEE ENSURE_CORRECT_NORMALS in the godot scene.glsl if we use shear etc and it looks weird
		NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

		if (fast && !ortho) {
			// broken with root scale
			vec4 screen = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
			vec4 proj = PROJECTION_MATRIX * screen;

			float point_size = length(vec3(MODELVIEW_MATRIX[0][0], MODELVIEW_MATRIX[1][0], MODELVIEW_MATRIX[2][0])) * root_scale;
			float sc = -screen.z;
			proj.xyz /= proj.w;
			// absolute display coordinates of the vertex
			vec2 adc = abs(proj.xy);
			vec2 vp_half = VIEWPORT_SIZE * 0.5;

			voxel_size = vec2(1.0) * point_size * VIEWPORT_SIZE.y * 0.75 / sc;
		} else {
			vec3 voxel_start = VERTEX - half_voxel;
			vec3 voxel_end = VERTEX + half_voxel;
			// voxel corners
			vec4 voxel = mvp * vec4(VERTEX, 1.0);
			voxel.xyz /= voxel.w;
			// project all 8 points of a cube to find the voxel's size on screen
			vec4 points[8] = {
				vec4(voxel_start.xyz, 1.0),
				vec4(voxel_start.xy, voxel_end.z, 1.0),
				vec4(voxel_start.x, voxel_end.yz, 1.0),
				vec4(voxel_start.x, voxel_end.y, voxel_start.z, 1.0),
				vec4(voxel_end.xyz, 1.0),
				vec4(voxel_end.xy, voxel_start.z, 1.0),
				vec4(voxel_end.x, voxel_start.yz, 1.0),
				vec4(voxel_end.x, voxel_start.y, voxel_end.z, 1.0)
			};

			voxel_size = vec2(0.0);
			int j = 0;
			vec2 vp_half = VIEWPORT_SIZE * 0.5;
			vec2 tl = vec2(10000.0);
			vec2 br = vec2(-10000.0);
			float min_z = 10000.0;
			float max_z = -10000.0;
			for (int i = 0; i < 8; i++) {
				points[i] = MODELVIEW_MATRIX * points[i];
				points[i].xyz /= points[i].w;
				tl = min(tl, points[i].xy);
				br = max(br, points[i].xy);
				min_z = min(min_z, points[i].z);
				max_z = max(max_z, points[i].z);
			}
			// voxel size is mostly correct at this z level
			float z = (max_z - min_z) * 0.5 + min_z;
			vec4 br_proj = PROJECTION_MATRIX * vec4(br, z, 1.0);
			vec4 tl_proj = PROJECTION_MATRIX * vec4(tl, z, 1.0);
			br_proj.xy /= br_proj.w;
			tl_proj.xy /= tl_proj.w;
			voxel_size = (br_proj.xy - tl_proj.xy);
			vec2 abs_display_coord = abs(voxel_size * 0.5 + tl_proj.xy);
			// if the voxel is outside the square center of the screen then the
			// distance between voxels needs to be enlarged to cover gaps..
			vec2 close = min(voxel_size * 10.0, max(0.0, 1.0 - voxel.z) * voxel_size * 200.0);
			vec2 edge = vec2(min(1.0, VIEWPORT_SIZE.y / VIEWPORT_SIZE.x), min(1.0, VIEWPORT_SIZE.x / VIEWPORT_SIZE.y));
			vec2 edge_boost = max(vec2(0.0), abs_display_coord - edge) * close;
			// For all targets except OpenGL+OpenXR y is a negative value here..
			voxel_size.y = abs(voxel_size.y);
			voxel_size += edge_boost * 0.1;
			voxel_size *= vp_half;
		}
		// screen door transparency if the voxel size is too small, reduces depth buffer overwrites
		// which improves performance a lot
		float mvs = max(voxel_size.x, voxel_size.y);
		// lod_bias allows control over the screendoor effect. 2.0 will be twice as early, 0.0 will disable it.
		if (mvs < lod_bias) {
			// each level of reduction will produce even fewer voxels
			float reduction = min(lod_worst, ceil(lod_bias / mvs));

			if (VERTEX_ID % int(floor(reduction)) >= 1) {
				voxel_size = vec2(0.0);
			} else if (reduction > 1.0) {
				voxel_size *= reduction * 1.0;
			}
		}
		if (phase_shift > 0.0) {
			VERTEX = phase_shift_vertex(VERTEX, phase_shift * voxel_size.x * PHASE_TRANSLATE);
			voxel_size *= 1.0 - phase_shift * (1.0 - PHASE_SHRINK);
		}
		POINT_SIZE = max(voxel_size.x, voxel_size.y);

		if (show_normals > 0.0) {
			COLOR = mix(COLOR, vec4(abs(nt_normal), 1.0), show_normals);
			if (length(nt_normal) == 0.0) {
				COLOR = vec4(1.0, 0, 1.0, 0);
			}
		}
		if (show_bone_weights > 0.0) {
			COLOR = mix(COLOR, bone_color, show_bone_weights);
		}

		// needed due to skip_vertex_transform
		// which we need because VERTEX.z isn't transformed by skeletons
		vec4 vert = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		vert.xyz /= vert.w;
		VERTEX.xyz = vert.xyz;
	}
}

void fragment() {
	vec2 base_uv = UV;
	ALBEDO = albedo.rgb * COLOR.rgb;
	if (super_black) {
		ALBEDO = ALBEDO * 0.99 + vec3(0.001);
	}
	float aspect_x = min(1.0, voxel_size.x / voxel_size.y * 0.5);
	float aspect_y = min(1.0, voxel_size.y / voxel_size.x * 0.5);
	vec2 edge = abs(POINT_COORD - 0.5) - (vec2(aspect_x, aspect_y));
	if (edge.x > 0.0 || edge.y > 0.0 || voxel_size == vec2(0.0)) {
		discard;
	}
	RIM = .05;
	RIM_TINT = 0.9;
	float metallic_tex = dot(texture(texture_metallic,base_uv),metallic_texture_channel);
	METALLIC = metallic_tex * metallic;
	float roughness_tex = dot(texture(texture_roughness,base_uv),roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;
	SPECULAR = specular;
}
