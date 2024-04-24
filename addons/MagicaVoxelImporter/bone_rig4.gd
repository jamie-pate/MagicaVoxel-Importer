@tool
extends Node3D

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

var _new_prefix = null
var _old_prefix = null
var _collecting_bones := false

func _ready():
	set_physics_process(false)
	if !Engine.is_editor_hint():
		# just remove ourself outside the editor
		queue_free()
	for a in get_children():
		if a is Area3D:
			a.monitorable = false
			a.monitoring = false


func _get_property_list():
	var result = [
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
		}
	]
	return result

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
	for a in get_children():
		var mirror_name = a.name.replace(from, to)
		var other = get_node_or_null(mirror_name)
		for c in a.get_children():
			if c is CollisionShape3D && a.name.find(from) > -1:
				var other_c := other.get_node_or_null(NodePath(c.name)) if other else null
				if other_c:
					other_c.global_transform.origin = c.global_transform.origin * Vector3(-1, 1, 1)
					other_c.global_transform.basis = c.global_transform.basis.rotated(Vector3.UP, deg_to_rad(180))

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
	var self_area = self
	var path = owner.get_parent().get_path_to(self) if owner && owner.get_parent() else get_path()
	if !mi || !skel:
		if is_inside_tree():
			if mesh_path && !mi:
				printerr('%s Mesh not found at path %s' % [path, mesh_path])
			if skeleton_path && !skel:
				printerr('%s Skeleton3D not found at path %s' % [path, skeleton_path])
			print('%s needs mesh_path:(%s) and skeleton_path:(%s)' % [path, !!mesh_path, !!skeleton_path])
		return
	if get_child_count() == 0:
		printerr("No child areas found")
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
	var bones_file = '%s.bones' % mesh.resource_path
	var weights_sz := 8 if mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
	assert(weights_sz == 4, "ARRAY_FLAG_USE_8_BONE_WEIGHTS is not supported")
	bones.resize(vert_count * weights_sz)
	weights.resize(vert_count * weights_sz)
	var area1 = get_children()[0]
	# we can just grab state from the first area, all other areas should share the same space
	var space := PhysicsServer3D.area_get_space(area1.get_rid())
	var state := PhysicsServer3D.space_get_direct_state(space)
	if area1.get_child_count() > 1:
		var area2 := get_children()[1]
		var space2 := PhysicsServer3D.area_get_space(area2.get_rid())
		assert(space2 == space)
		var state2 := PhysicsServer3D.space_get_direct_state(space2)
		assert(state2 == state2)
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
	var bone_counts := {}
	var bone_overlap := {}

	var w := PackedFloat32Array()
	for i in range(weights_sz):
		w.append(0.0)
	for a in get_children():
		assert(a is Area3D, "All children must be Area3D")
		assert(a.collision_mask == 0)
		a.collision_layer = 1
		for c in a.get_children():
			assert(c is CollisionShape3D, "All grandchildren must be CollisionShape3D")
	var fail := []
	for i in len(vertices):
		var v := vertices[i]

		qp.transform = mi.global_transform * Transform3D(Basis(), v)
		var collisions := state.intersect_shape(qp, weights_sz)
		var c_len = len(collisions)
		if !c_len:
			missing_voxels.append(qp.transform.origin)

		var bone_count := 0
		var collided_bones := []
		var b_i = weights_sz * i
		var b := 0
		while b < weights_sz:
			w[b] = 0.0
			var found := false
			if b < c_len && b_i + b < vert_count * weights_sz:
				var shape_idx := collisions[b].shape as int
				var bone_area = collisions[b].collider
				if bone_area.get_parent() != self:
					printerr('Collided %s with something else? %s' % [
						qp.transform.origin,
						bone_area.get_path()
					])
				else:
					# if multiple shapes in the same area capture the same voxel,
					# use the first collision in tree order
					var bone_name = bone_area.name
					if bone_name in collided_bones:
						collisions.erase(collisions[b])
						c_len = len(collisions)
						continue
					found = true
					bone_count += 1
					var skel_bone_name = "%s%s" % [bone_prefix, bone_name]

					var bone := skel.find_bone(skel_bone_name)
					if bone == -1:
						fail.append('Unable to find bone %s' % [skel_bone_name])
					bones[b_i + b] = bone
					if !bone_name in bone_counts:
						bone_counts[bone_name] = 0
					collided_bones.append(bone_name)
					bone_counts[bone_name] += 1
			if !found:
				bones[b_i + b] = 0
			b += 1
		if len(collisions) > weights_sz:
			collisions.resize(weights_sz)
		if len(collisions) == 1:
			for w_i in len(w):
				w[w_i] = 1.0 if w_i == 0 else 0.0
		else:
			var area_w_map := {}
			for c_i in len(collisions):
				area_w_map[collisions[c_i].collider] = c_i
			for pair in _pairs(collisions):
				var p_w := _calc_bone_weights(state, pair[0].collider, pair[1].collider, qp.transform.origin)
				for p_i in [0, 1]:
					b = area_w_map[pair[p_i].collider]
					w[b] = p_w[p_i]
		var total_check := 0.0
		var weight_total := 0.0
		b = 0
		while b < weights_sz:
			weight_total += w[b]
			b += 1
		b = 0
		while b < weights_sz:
			var bw = w[b] / weight_total if weight_total > 0 else 0.0
			weights[b_i + b] = bw
			total_check += weights[b_i + b]
			b += 1
		if len(collided_bones) > 1:
			collided_bones.sort()

			if !collided_bones in bone_overlap:
				bone_overlap[collided_bones] = 0
			bone_overlap[collided_bones] += 1
	for a in get_children():
		a.collision_layer = 0
	PhysicsServer3D.free_rid(voxel)
	if fail:
		printerr('Fatal error: %s' % ['\n'.join(fail.slice(0, 10))])
		return
	var bone_ids = {}
	for bone in bone_counts:
		bone_ids[bone] = skel.find_bone("%s%s" % [bone_prefix, bone])
	print('\noverlap:\n%s\n\nbones:\n%s\n\nids:\n%s\n' % [bone_overlap, bone_counts, bone_ids])
	if len(missing_voxels) == len(vertices):
		printerr('No collisions found!')
		return
	if missing_voxels:
		printerr('##### WARNING #####\nNo collision for %s voxels at %s...!' % [
			len(missing_voxels),
			missing_voxels.slice(0, 10)
		])

	var f := FileAccess.open(bones_file, FileAccess.WRITE | FileAccess.COMPRESSION_ZSTD)
	if !f:
		printerr('Unable to write to bones file %s: %s' % [bones_file, FileAccess.get_open_error()])
		return
	var bytes := var_to_bytes(bones)
	f.store_32(len(bytes))
	f.store_buffer(bytes)
	bytes = var_to_bytes(weights)
	f.store_32(len(bytes))
	f.store_buffer(bytes)
	f.close()

	print('Saved to %s bones: %s weights: %s' % [
		bones_file,
		len(bones),
		len(weights)
	])
	print('Bone Collection took %sms' % [Time.get_ticks_msec() - start])
	# big hack...
	if auto_reimport:
		call_deferred('re_import')


# Return each unique pair of items from all items of an array
func _pairs(array):
	var result := []
	for i in range(len(array)):
		for j in range(i + 1, len(array)):
			result.append([array[i], array[j]])
	return result


func _get_area_center(area: Area3D) -> Vector3:
	# be lazy and just take the average center of all shapes as the 'center'
	# to choose the ray direction
	var aabb = null
	for s in area.get_children():
		if !s.disabled:
			var s_origin: Vector3 = s.global_transform.origin
			aabb = aabb.expand(s_origin) if aabb else AABB(s_origin, Vector3())
	assert(aabb, "Area has no children? %s" % [area.get_path()])
	return aabb.get_center()


func _ray_into(state: PhysicsDirectSpaceState3D, area: Area3D, ray_direction: Vector3, to_voxel: Vector3):
	var exclude := []
	for a in get_children():
		if a != area:
			exclude.append((a as Area3D).get_rid())
	var ray_len := 10000.0
	var ray_end := to_voxel

	var ray_start := ray_end + ray_direction * -ray_len
	var ray_params := PhysicsRayQueryParameters3D.create(ray_start, ray_end, ~0, [])
	ray_params.collide_with_bodies = false
	ray_params.collide_with_areas = true
	ray_params.exclude = exclude
	var intersect = state.intersect_ray(ray_params)
	if intersect:
		return intersect.position
	else:
		# assume we want 0 weight if we don't collide (on the edge)
		return null


func _calc_bone_weights(state: PhysicsDirectSpaceState3D, a1: Area3D, a2: Area3D, origin: Vector3) -> Array[float]:
	"""
	Get the unnormalized bone weight for a bone based on the distance to the edge of the shape.
	Calculates the ray for each shape pair that overlaps for this voxel
	and sum the distances along that ray to the outside of the shape for each shape?
	"""
	var RAY_LEN = 1000.0
	var bone1_name = a1.name
	var bone2_name = a2.name
	var exclude = []
	var c1 := _get_area_center(a1)
	var c2 := _get_area_center(a2)
	var p1 = _ray_into(state, a1, (c1 - c2).normalized(), origin)
	var p2 = _ray_into(state, a2, (c2 - c1).normalized(), origin)
	return [p1.distance_to(origin) if p1 else 0, p2.distance_to(origin) if p2 else 0]


func re_import():
	if Engine.is_editor_hint():
		var mi := get_node_or_null(mesh_path) as MeshInstance3D
		if !mi:
			return
		var mesh := mi.mesh as ArrayMesh
		if !mesh:
			return
		var ei := EditorInterface
		var bc: Control
		bc = ei.get_base_control()
		if bc:
			# super duper big hack
			var import = bc.find_child('Import', true, false)
			if import:
				import._reimport()
