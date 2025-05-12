@tool
extends MeshInstance3D

@export var render_head: bool: set = _set_render_head
@export var phase_shift: float: set = _set_phase_shift
@export var super_black: bool: set = _set_super_black

func _ready():
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


func get_neck_height() -> float:
	return get_bone_height("Neck")


func get_head_height() -> float:
	# try to get the 'head top' bone if it exists, otherwise head
	var h := get_bone_height("Head", true)
	if h > 0:
		return h
	return get_bone_height("Head")


func get_bone_height(bone, child_of := false) -> float:
	var skel := get_node_or_null(skeleton) as Skeleton3D
	var height := 0.0
	if skel:
		for i in skel.get_bone_count():
			# assuming default godot bonemap names for bones
			var bone_name = skel.get_bone_name(i)
			if child_of:
				var p := skel.get_bone_parent(i)
				if p > -1:
					bone_name = skel.get_bone_name(p)
			if bone_name == bone:
				var tfm := skel.get_bone_rest(i)
				height += tfm.origin.y
				var p = i
				while true:
					p = skel.get_bone_parent(p)
					if p < 0:
						break
					tfm = skel.get_bone_rest(p)
					height += tfm.origin.y
				break
	return height

func _set_render_head(value):
	render_head = value
	if is_inside_tree():
		var mat:ShaderMaterial= get_instance_mat()
		var neck_bone_index := -1
		var head_bone_index := -1
		if mat && mat.get_shader_parameter("render_head") != value:
			if !value:
				var skel := get_node_or_null(skeleton) as Skeleton3D
				if skel:
					for i in skel.get_bone_count():
						# assuming default godot bonemap names for bones
						var bone_name = skel.get_bone_name(i)
						if bone_name == "Head":
							head_bone_index = i
						if bone_name == "Neck":
							neck_bone_index = i
					mat.set_shader_parameter("head_bone_index", head_bone_index)
					mat.set_shader_parameter("neck_bone_index", neck_bone_index)
			if neck_bone_index >= 0 && head_bone_index >= 0 || value:
				mat.set_shader_parameter("render_head", value)
			#mat.inspect_native_shader_code()



func _set_phase_shift(value):
	phase_shift = value
	if is_inside_tree():
		var mat = get_instance_mat()
		if mat && mat.get_shader_parameter("phase_shift") != value:
			mat.set_shader_parameter("phase_shift", value)


func _set_super_black(value):
	super_black = value
	if is_inside_tree():
		var mat = get_instance_mat()
		if mat && mat.get_shader_parameter("super_black") != value:
			mat.set_shader_parameter("super_black", value)


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
