@tool
extends Area3D

signal _physics_collide_bones()

# todo: plugin menu?
# in the meantime you can check 'Collect Bones' to manually run the tool script
@export var collect_bones := false: set = _set_collect_bones
@export var mirror_ltr := false: set = _set_mirror_ltr
@export var mirror_rtl := false: set = _set_mirror_rtl
@export var auto_reimport := true

# magic property that will update the prefix on ALL rig children!
@export var bone_prefix: String: set = _set_bone_prefix

# These 3 are exported below using _get_property_list
var mesh_path: NodePath: set = _set_mesh_path
var skeleton_path: NodePath: set = _set_skeleton_path
var area_path: NodePath: set = _set_area_path

@export var blend_factor: float = 1.0

var _new_prefix = null
var _old_prefix = null
var _collecting_bones := false

func _ready():
	set_physics_process(false)
	if !Engine.is_editor_hint():
		for c in get_children():
			if c is CollisionShape3D:
				c.disabled = true
	monitoring = false
	monitorable = false

func _get_property_list():
	return [
		{
			name='skeleton_path',
			type=TYPE_NODE_PATH,
			hint=PROPERTY_HINT_NODE_PATH_VALID_TYPES,
			hint_string='Skeleton3D'
		},
		{
			name='mesh_path',
			type=TYPE_NODE_PATH,
			hint=PROPERTY_HINT_NODE_PATH_VALID_TYPES,
			hint_string='MeshInstance3D'
		},
		{
			name='area_path',
			type=TYPE_NODE_PATH,
			hint=PROPERTY_HINT_NODE_PATH_VALID_TYPES,
			hint_string='Area3D'
		}
	]

func _set_collect_bones(value):
	if !collect_bones && value:
		_collect_bones_once()

func _set_mirror_ltr(value):
	mirror_ltr = value
	if value:
		_mirror_shapes('Left', 'Right')
	mirror_ltr = false

func _set_mirror_rtl(value):
	mirror_rtl = value
	if value:
		_mirror_shapes('Right', 'Left')
	mirror_rtl = false

func _mirror_shapes(from: String, to: String):
	for c in get_children():
		if c is CollisionShape3D && c.name.find(from) > -1:
			var mirror_name = c.name.replace(from, to)
			var other = get_node_or_null(mirror_name)
			if other:
				other.transform.origin = c.transform.origin * Vector3(-1, 1, 1)
				other.transform.basis = c.transform.basis.rotated(Vector3.UP, deg_to_rad(180))

func _set_bone_prefix(value):
	if value == bone_prefix:
		return
	_new_prefix = value
	# debounce because this will remove focus from the inspector..
	var first_run = _old_prefix == null
	if !first_run:
		await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self) && is_inside_tree() && _new_prefix == value:
		# this is the initial load
		_old_prefix = bone_prefix
		bone_prefix = value
		if !first_run:
			print('replacing bone prefix %s > %s' % [_old_prefix, bone_prefix])
			for c in get_children():
				if c.name.begins_with(_old_prefix):
					c.name = bone_prefix + c.name.trim_prefix(_old_prefix)

func _set_mesh_path(value: NodePath):
	mesh_path = value
	_collect_bones_once()

func _set_skeleton_path(value: NodePath):
	skeleton_path = value
	_collect_bones_once()

func _set_area_path(value: NodePath):
	area_path = value
	_collect_bones_once()


func _shape_name_to_bone_name(value: String):
	var parts = value.rsplit('#', 1)
	return parts[0] if len(parts) else ''

func _collect_bones_once():
	if is_inside_tree() && !collect_bones && Engine.is_editor_hint():
		if !self in EditorInterface.get_selection().get_selected_nodes():
			return
		if _collecting_bones:
			return
		_collecting_bones = true
		collect_bones = true
		_collect_bones()
		collect_bones = false
		await get_tree().process_frame
		if is_instance_valid(self):
			_collecting_bones = false

func _collect_bones():
	if !is_inside_tree():
		# this gets called when you set mesh/skeleton/area paths but we don't really want
		# to do it if you are just loading the scene
		return
	var start := Time.get_ticks_msec()
	var skel := get_node_or_null(skeleton_path) as Skeleton3D
	var mi := get_node_or_null(mesh_path) as MeshInstance3D
	var area := get_node_or_null(area_path) as Area3D
	var self_area = self
	var path = owner.get_parent().get_path_to(self) if owner && owner.get_parent() else get_path()
	if !area && self_area is Area3D:
		area = self_area
	if !mi || !skel:
		if is_inside_tree():
			if mesh_path && !mi:
				printerr('%s Mesh not found at path %s' % [path, mesh_path])
			if skeleton_path && !skel:
				printerr('%s Skeleton3D not found at path %s' % [path, skeleton_path])
			if area_path && !area:
				printerr('%s Area3D not found at path %s' % [path, area_path])
			print('%s needs mesh_path:(%s) and skeleton_path:(%s)' % [path, !!mesh_path, !!skeleton_path])
		return
	var mesh := mi.mesh as ArrayMesh
	if !mesh:
		printerr('%s Mesh %s is not an arraymesh' % [path, mesh])
		return
	if !mesh.resource_path:
		printerr('%s Mesh %s has no resource path' % [path, mesh])
		return
	if mesh.get_surface_count() < 1:
		printerr('%s Mesh %s has no surface' % [path, mesh])
		return
	# TODO: support additional surfaces?

	var s := 0
	var surface := mesh.surface_get_arrays(s)
	var vertices := surface[ArrayMesh.ARRAY_VERTEX] as PackedVector3Array
	var bones = surface[ArrayMesh.ARRAY_BONES]
	if !bones is PackedInt32Array:
		if bones is PackedFloat32Array:
			print('bones is PackedFloat32Array')
		elif !bones:
			bones = PackedInt32Array()
		else:
			printerr('bones is %s' % typeof(bones))
	var weights : PackedFloat32Array = surface[ArrayMesh.ARRAY_WEIGHTS] if surface[ArrayMesh.ARRAY_WEIGHTS] else PackedFloat32Array()

	print('verts: %s bones: %s weights: %s ' %  [len(vertices), len(bones), len(weights)])
	var vert_count = len(vertices)
	var import_file = '%s.import' % mesh.resource_path
	if !FileAccess.file_exists(import_file):
		printerr('Import file does not exist: %s' % [import_file])
		return
	var f := FileAccess.open(import_file, FileAccess.READ)
	if !f:
		printerr('Unable to read from import file %s: %s' % [import_file, FileAccess.get_open_error()])
		return
	var weights_sz := 8 if mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
	assert(weights_sz == 4, "ARRAY_FLAG_USE_8_BONE_WEIGHTS is not supported")
	bones.resize(vert_count * weights_sz)
	weights.resize(vert_count * weights_sz)
	var space := PhysicsServer3D.area_get_space(area.get_rid())
	var state := PhysicsServer3D.space_get_direct_state(space)
	var USE_BOX = false
	var voxel = PhysicsServer3D.box_shape_create() if USE_BOX else PhysicsServer3D.sphere_shape_create()

	var root_scale := 1.0
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	if mat:
		root_scale = mat.get_shader_parameter('root_scale')
	var data = mi.scale * 0.5 * root_scale
	if USE_BOX:
		PhysicsServer3D.shape_set_data(voxel, data)
	else:
		PhysicsServer3D.shape_set_data(voxel, data.x)
	var qp := PhysicsShapeQueryParameters3D.new()

	qp.shape_rid = voxel
	qp.collide_with_areas = true
	qp.collide_with_bodies = false
	var missing_voxels := []
	var bone_map = {}
	var bone_overlap = {}

	var w := PackedFloat32Array()
	for i in range(weights_sz):
		w.append(0.0)
	var enabled_shapes := {}
	for c in area.get_children():
		if c is CollisionShape3D && !c.disabled:
			var bone_name = _shape_name_to_bone_name(c.name)
			if !bone_name in enabled_shapes:
				enabled_shapes[bone_name] = []
			enabled_shapes[bone_name].append(c)
	assert(area.collision_mask == 0)
	var fail := []
	area.collision_layer = 1
	for i in len(vertices):
		var v := vertices[i]

		qp.transform = mi.global_transform * Transform3D(Basis(), v)
		var collisions := state.intersect_shape(qp, weights_sz)
		var weight_total := 0.0
		var c_len = len(collisions)
		if !c_len:
			missing_voxels.append(qp.transform.origin)

		var bone_count := 0
		var bone_names := []
		var b_i = weights_sz * i
		var b := 0
		while b < weights_sz:
			w[b] = 0.0
			var found := false
			if b < c_len && b_i + b < vert_count * weights_sz:
				var shape_idx := collisions[b].shape as int
				var collider = collisions[b].collider
				if collider != area:
					printerr('Collided %s with something else? %s' % [
						qp.transform.origin,
						collider
					])
				else:
					var shape = area.shape_owner_get_owner(area.shape_find_owner(shape_idx))
					var bone_name = _shape_name_to_bone_name(shape.name)
					# if multiple shapes capture the same voxel, use the first one in tree order
					if bone_name in bone_names:
						collisions.erase(collisions[b])
						c_len = len(collisions)
						continue
					if c_len == 1:
						w[b] = 1.0
					else:
						var weight = _calc_bone_weight(area, enabled_shapes, shape, state, qp.transform.origin)
						if weight:
							w[b] = weight
					weight_total += w[b]
					if !bone_name in bone_map:
						bone_map[bone_name] = 0
					bone_names.append(bone_name)
					bone_map[bone_name] += 1
					var bone := skel.find_bone(bone_name)
					if bone == -1:
						fail.append('Unable to find bone %s' % [bone_name])
						printerr()
					found = true
					bone_count += 1
					bones[b_i + b] = bone
					# TODO: distribute weights?
			if !found:
				bones[b_i + b] = 0
			b += 1
		b = 0
		while b < weights_sz:
			var bw = w[b] / weight_total if weight_total > 0 else 0.0
			if blend_factor != 1.0:
				bw = max(0.0, min(1.0, (bw - 0.5) * blend_factor + 0.5))
			weights[b_i + b] = bw
			b += 1
		if len(bone_names) > 1:
			bone_names.sort()
			if !bone_names in bone_overlap:
				bone_overlap[bone_names] = 0
			bone_overlap[bone_names] += 1

	area.collision_layer = 0
	PhysicsServer3D.free_rid(voxel)
	if fail:
		printerr('Fatal error: %s' % ['\n'.join(fail.slice(0, 10))])
		return
	var bone_ids = {}
	for bone in bone_map:
		bone_ids[bone] = skel.find_bone(bone)
	print('\noverlap:\n%s\n\nbones:\n%s\n\nids:\n%s\n' % [bone_overlap, bone_map, bone_ids])
	if len(missing_voxels) == len(vertices):
		printerr('No collisions found!')
		return
	if missing_voxels:
		printerr('##### WARNING #####\nNo collision for %s voxels at %s...!' % [
			len(missing_voxels),
			missing_voxels.slice(0, 10)
		])

	var lines := PackedStringArray()
	while !f.eof_reached():
		var line := f.get_line()
		if !line.begins_with('bones=') && !line.begins_with('weights='):
			lines.append(line)
	f.close()
	if len(lines) && lines[len(lines) - 1] == '':
		lines.remove_at(len(lines) - 1)
	f = FileAccess.open(import_file, FileAccess.WRITE)
	if !f:
		printerr('Unable to write to import file %s: %s' % [import_file, FileAccess.get_open_error()])
		return
	for l in lines:
		f.store_line(l)
	f.store_line('bones=%s' % [var_to_str(bones)])
	f.store_line('weights=%s' % [var_to_str(weights)])
	f.close()

	print('Saved to %s bones: %s weights: %s' % [
		import_file,
		len(bones),
		len(weights)
	])
	print('Bone Collection took %sms' % [Time.get_ticks_msec() - start])
	# big hack...
	if collect_bones && auto_reimport:
		call_deferred('re_import')


func _calc_bone_weight(area: Area3D, enabled_shapes: Dictionary, shape: CollisionShape3D, state: PhysicsDirectSpaceState3D, origin: Vector3) -> float:
	"""
	Get the unnormalized bone weight for a bone based on the distance to the edge of the shape
	Currently measures the distance from the origin to the outside of the shape
	along a the vector between the origin and the shape's origin
	This method of smoothing requires a lot of extra volume in the shapes to blend
	on the correct axis...

	TODO: calculate the ray for each shape pair that overlaps for this voxel
	and sum the distances along that ray to the outside of the shape for each shape?
	"""
	var RAY_LEN = 10000.0
	var bone_name = _shape_name_to_bone_name(shape.name)
	var exclude := []
	for n in enabled_shapes:
		if n != bone_name:
			for es in enabled_shapes[n]:
				exclude.append(es.shape.get_rid())
	var ray_end = shape.global_transform.origin
	# ray points toward the center of the shape from the current voxel
	var ray = ray_end - origin
	var ray_start = ray_end - ray.normalized() * RAY_LEN
	var ray_param = PhysicsRayQueryParameters3D.create(ray_start, ray_end, ~0, [])
	ray_param.collide_with_bodies = false
	ray_param.collide_with_areas = true
	ray_param.exclude = exclude
	var intersect = state.intersect_ray(ray_param)
	if intersect:
		return intersect.position.distance_to(origin)
	else:
		printerr("intersection didn't work with %s %s > %s" % [shape.name, ray_start, ray_end])
		return 0.0

func re_import():
	if Engine.is_editor_hint():
		var mi := get_node_or_null(mesh_path) as MeshInstance3D
		if !mi:
			return
		var mesh := mi.mesh as ArrayMesh
		if !mesh:
			return
		var bc: Control
		for c in get_tree().root.get_node('EditorNode').get_children():
			if c.is_class('EditorInterface'):
				c.edit_resource(mesh)
				c.inspect_object(self)
				bc = c.get_base_control()
				break
		if bc:
			# super duper big hack
			var import = bc.find_child('Import', true, false)
			if import:
				import._reimport()
