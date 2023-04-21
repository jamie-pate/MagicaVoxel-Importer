tool
extends MeshInstance

export(float) var neck_height setget _set_neck_height
export(bool) var render_head setget set_render_head

func _ready():
	_set_neck_height(neck_height)
	set_render_head(true)

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

func set_render_head(value):
	if is_inside_tree():
		render_head = value
		var vox_char_node := $"." as MeshInstance
		var mat = vox_char_node.get_surface_material(0)
		if !mat:
			mat = vox_char_node.mesh.surface_get_material(0).duplicate()
			if !Engine.is_editor_hint():
				vox_char_node.set_surface_material(0, mat)
			if mat.get_shader_param("render_head") == value:
				return
		mat.set_shader_param("render_head", value)
