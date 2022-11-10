tool
extends MeshInstance

export(float) var neck_height setget _set_neck_height
export(bool) var render_head setget _set_render_head


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
	if mesh:
		for mat in _get_mats():
			mat.set_shader_param("render_head",value)
