@tool
extends MeshInstance3D

@export var neck_height: float: set = _set_neck_height
@export var render_head: bool: set = _set_render_head
@export var phase_shift: float: set = _set_phase_shift

func _ready():
	_set_neck_height(neck_height)
	_set_render_head(true)


func _strip_gles3_from_shader():
	if Engine.is_editor_hint():
		return
	var mat = mesh.surface_get_material(0) as ShaderMaterial
	if !mat || mat.gdshader.has_meta('gles3_stripped'):
		return
	var strip_expr = RegEx.new()
	strip_expr.compile("(?s)\\/\\/ #ifndef GLES3.+?\\/\\/ #endif")
	var code = mat.gdshader.code
	var stripped_code = strip_expr.sub(code, '', true)
	if code != stripped_code:
		mat.gdshader.code = stripped_code
		mat.gdshader.set_meta('gles3_stripped', true)


func _get_mats() -> Array:
	var result = []
	var mat = mesh.surface_get_material(0) if mesh && mesh.get_surface_count() else null
	if mat:
		result.append(mat)
	mat = get_surface_override_material(0) if get_surface_override_material_count() else null
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
			mat.set_shader_parameter('neck_height', value)


func _set_render_head(value):
	render_head = value
	if is_inside_tree():
		var mat = get_instance_mat()
		if mat && mat.get_shader_parameter("render_head") != value:
			mat.set_shader_parameter("render_head", value)


func _set_phase_shift(value):
	phase_shift = value
	if is_inside_tree():
		var mat = get_instance_mat()
		if mat && mat.get_shader_parameter("phase_shift") != value:
			mat.set_shader_parameter("phase_shift", value)


## Get a material that's unique to this instance
## except in the editor, where that's a bad idea
func get_instance_mat() -> ShaderMaterial:
	if !mesh || get_surface_override_material_count() < 1:
		return null
	var mat := get_surface_override_material(0) as ShaderMaterial
	if !mat:
		mat = mesh.surface_get_material(0)
		if !Engine.is_editor_hint():
			mat = mat.duplicate()
			set_surface_override_material(0, mat)
	return mat
