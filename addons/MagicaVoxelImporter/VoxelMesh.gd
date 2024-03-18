tool
extends MeshInstance

export(float) var neck_height setget _set_neck_height
export(bool) var render_head setget _set_render_head
export(float, 0.0, 1.0) var phase_shift setget _set_phase_shift

func _ready():
	_set_neck_height(neck_height)
	_set_render_head(true)
	if OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES2:
		_strip_gles3_from_shader()


func _strip_gles3_from_shader():
	if Engine.editor_hint:
		return
	var mat = mesh.surface_get_material(0) as ShaderMaterial
	if !mat || mat.shader.has_meta('gles3_stripped'):
		return
	var strip_expr = RegEx.new()
	strip_expr.compile("(?s)\\/\\/ #ifndef GLES3.+?\\/\\/ #endif")
	var code = mat.shader.code
	var stripped_code = strip_expr.sub(code, '', true)
	if code != stripped_code:
		mat.shader.code = stripped_code
		mat.shader.set_meta('gles3_stripped', true)


func _get_mats() -> Array:
	var result = []
	var mat = mesh.surface_get_material(0) if mesh && mesh.get_surface_count() else null
	if mat:
		result.append(mat)
	mat = get_surface_material(0) if get_surface_material_count() else null
	if mat:
		result.append(mat)
	mat = material_override
	if mat:
		result.append(mat)
	return result


func _set_neck_height(value):
	neck_height = value
	if mesh:
		for mat in _get_mats():
			mat.set_shader_param('neck_height', value)


func _set_render_head(value):
	render_head = value
	if is_inside_tree():
		var mat = get_instance_mat()
		if mat && mat.get_shader_param("render_head") != value:
			mat.set_shader_param("render_head", value)


func _set_phase_shift(value):
	phase_shift = value
	if is_inside_tree():
		var mat = get_instance_mat()
		if mat && mat.get_shader_param("phase_shift") != value:
			mat.set_shader_param("phase_shift", value)


## Get a material that's unique to this instance
## except in the editor, where that's a bad idea
func get_instance_mat() -> ShaderMaterial:
	if !mesh || get_surface_material_count() < 1:
		return null
	var mat := get_surface_material(0) as ShaderMaterial
	if !mat:
		mat = mesh.surface_get_material(0)
		if !Engine.is_editor_hint():
			mat = mat.duplicate()
			set_surface_material(0, mat)
	return mat
