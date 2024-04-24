extends RefCounted
const shader = preload('./points.gdshader')

const MAX_AXIS_SIZE = 256
const TIME_DBG = false

var _time := 0

class MV extends RefCounted:
	# revive a string from the stream
	func mv_str(file):
		var size = file.get_32()
		var buff = file.get_buffer(size)
		# assume utf8? not sure, but should be safe
		return buff.get_string_from_utf8()

	# revive a dict from the stream
	func mv_dict(file: FileAccess):
		var size = file.get_32()
		var result = {}
		for i in size:
			# dict values are always strings...
			var key = mv_str(file)
			result[key] = mv_str(file)
		return result

class MVChunk extends RefCounted:
	var id
	var size
	var child_count
	var position
	var header_position

	func init(file):
		header_position = file.get_position()
		id = PackedByteArray([file.get_8(),file.get_8(),file.get_8(),file.get_8()]).get_string_from_ascii() #char[] chunkId
		size = file.get_32()
		child_count = file.get_32()
		position = file.get_position()
		#print('id:%s sz:%d cc:%d' % [id, size, child_count])

class MVVoxels extends RefCounted:
	var pos := Vector3(0,0,0)
	var color_idx: int
	var color: Color
	var normal := Vector3(0, 0, 0)
	var neighbour_normals := Vector3(0, 0, 0)

	# contain which chunk we are in so we can find it's name later?
	var chunkNum = -1

	# each voxel starts with x(right), y(up), z(forward), color_idx values
	# y is up and -z is forward in godot, so we swap those here.
	func init(file: FileAccess):
		pos.x = file.get_8()
		pos.z = -file.get_8()
		pos.y = file.get_8()

		color_idx = file.get_8()

	func _to_string():
		return 'MVVoxels pos:%s color:%s normal:%s chunkNum:%s' % [pos, color, normal, chunkNum]


class VoxData extends RefCounted:
	class Vox3 extends RefCounted:
		var x := 0
		var y := 0
		var z := 0

		func _init(vector := Vector3()):
			x = int(round(vector.x))
			y = int(round(vector.y))
			z = int(round(vector.z))

		func _to_string():
			return str(Vector3(x, y, z))

		func volume():
			return x * y * z

		func wrapped(size: Vox3) -> Vox3:
			var result := Vox3.new()
			result.x = x
			result.y = y
			result.z = z
			while result.x < 0:
				result.x += size.x
			while result.y < 0:
				result.y += size.y
			while result.z < 0:
				result.z += size.z
			result.x = result.x % size.x
			result.y = result.y % size.y
			result.z = result.z % size.z
			return result

	# always use a dictionary as it's faster?
	# maybe some dense models may be faster with array?
	const MAX_ARRAY_VOLUME = 0# 1024 * 1024 * 1024

	var dict_data := {}
	var array_data := []
	var size := Vox3.new()
	# extents are separate properties because even 2 vector3s was slower!
	var aabb_start_x := 10000.0
	var aabb_start_y := 10000.0
	var aabb_start_z := 10000.0
	var aabb_end_x := -10000.0
	var aabb_end_y := -10000.0
	var aabb_end_z := -10000.0
	var use_dict := false
	var reported := 0
	var t := PackedInt64Array([0, 0, 0, 0, 0, 0])


	func _init(_size: Vector3):
		size = Vox3.new(_size)
		var volume = size.volume()
		if volume > MAX_ARRAY_VOLUME:
			use_dict = true
		else:
			array_data.resize(volume)

	func _coord_idx(x: int, y: int, z: int) -> int:
		while x < 0:
			x += size.x
		if x > size.x:
			x = x % size.x
		while y < 0:
			y += size.y
		if y > size.y:
			y = y % size.y
		while z < 0:
			z += size.z
		if z > size.z:
			z = z % size.z
		var idx := x + (y * size.x) + (z * size.x * size.y)
		if idx < 0:
			idx = 0
			printerr('idx < 0! %s' % [[x, y, z]])
		return idx

	func get_vox(pos: Vector3) -> MVVoxels:
		# note: don't create vox3 for xyz because it's too slow
		var start = Time.get_ticks_usec()
		if !(pos.x >= aabb_start_x && pos.y >= aabb_start_y && pos.z >= aabb_start_z && \
				pos.x <= aabb_end_x && pos.y <= aabb_end_y && pos.z <= aabb_end_z):
			t[1] = t[1] + (Time.get_ticks_usec() - start)
			return null
		var end = Time.get_ticks_usec()
		t[1] = t[1] + (end - start)
		start = end
		var result
		if use_dict:
			result = dict_data.get(pos)
		else:

			var x = int(pos.x)
			var y = int(pos.y)
			var z = int(pos.z)
			end = Time.get_ticks_usec()
			t[0] = t[0] + (end - start)
			start = end

			var idx := _coord_idx(x, y, z)
			end = Time.get_ticks_usec()
			t[2] = t[2] + (end - start)
			start = end

			result = array_data[idx]
		t[3] = t[3] + (Time.get_ticks_usec() - start)
		return result

	func set_vox(value: MVVoxels) -> void:
		var pos := value.pos

		if pos.x < aabb_start_x:
			aabb_start_x = pos.x
		if pos.y < aabb_start_y:
			aabb_start_y = pos.y
		if pos.z < aabb_start_z:
			aabb_start_z = pos.z
		if pos.x > aabb_end_x:
			aabb_end_x = pos.x
		if pos.y > aabb_end_y:
			aabb_end_y = pos.y
		if pos.z > aabb_end_z:
			aabb_end_z = pos.z
		if use_dict:
			dict_data[pos] = value
		else:
			# this is the slow part!
			var x := int(pos.x)
			var y := int(pos.y)
			var z := int(pos.z)
			var idx := _coord_idx(x, y, z)
			array_data[idx] = value

	# NOTE: values in the result may be null
	func voxels():
		if use_dict:
			return dict_data.values()
		else:
			return array_data.duplicate()

	# align the center to match the way the center is calculated in mv
	func center():
		var start = Vector3(aabb_start_x, aabb_start_y, aabb_start_z)
		var size = Vector3(aabb_end_x - aabb_start_x, aabb_end_y - aabb_start_y, aabb_end_z - aabb_start_z) + Vector3.ONE
		# mv calculates it's Y in the opposite direction
		# so we need to flip godot Z before using floor() and then flip it back
		var half = (size * Vector3(0.5, 0.5, -0.5)).floor() * Vector3(1, 1, -1)
		var center = half + start

		# move it all up 0.5 voxels to center each voxel's origin
		return center - Vector3.ONE * 0.5

class MVGroupNode extends MV:
	var node_id: int
	var attr := {}
	var child_count: int
	var child_ids := PackedInt32Array()
	var children := []

	func _to_string():
		return 'group %s children: %s' % [node_id, child_ids]

	func init(file):
		node_id = file.get_32()
		attr = mv_dict(file)
		child_count = file.get_32()
		for i in child_count:
			child_ids.append(file.get_32())

class MVShapeNode extends MV:
	var node_id: int
	var attr := {}
	var model_count: int
	var model_data := []
	var models := []

	func _to_string():
		return 'shape %s models: %s' % [node_id, model_data]

	func init(file):
		node_id = file.get_32()
		attr = mv_dict(file)
		model_count = file.get_32()
		for i in model_count:
			model_data.append({
				model_id=file.get_32(),
				attributes=mv_dict(file)
			})

class MVTransformNode extends MV:
	var node_id
	var name: String
	var attr
	var child_node_id
	var child #MVGroupNode | MVShapeNode
	var reserved_id
	var layer_id
	var frame_count
	var frames: Array
	var origin := Vector3()
	var basis := Basis()

	func _to_string():
		return 'transform %s child: %s origin: %s basis: %s' % [
			node_id,
			child_node_id,
			origin,
			basis
		]

	func init(file):
		node_id = file.get_32()
		attr = mv_dict(file)
		# '_name', _hidden '0'/'1'
		name = attr._name if '_name' in attr else ''
		child_node_id = file.get_32()
		reserved_id = file.get_32()
		layer_id = file.get_32()
		frame_count = file.get_32()
		frames = []
		if frame_count != 1:
			printerr('Unsupported frame count for transform: %s' % [frame_count])
		assert(frame_count == 1)
		for i in frame_count:
			# {'_r': 'int8?', '_t': '00 00 33', '_f': '1234'
			var frame = mv_dict(file)
			frames.append(frame)
			if '_r' in frame:
				basis = mv_rot_to_basis(int(frame._r))
			if '_t' in frame:

				var o = frame._t.split(' ')
				if len(o) == 3:
					# Z is 'up' in magicavoxel, forward y is negative
					origin = Vector3(int(o[0]), int(o[2]), -int(o[1]))
				else:
					printerr('Invalid _t position: %s' % [frame._t])

	func mv_rot_to_basis(byte: int):
		# so stupidly complicated... also Z is 'up'
		var vectors = [Vector3(1, 0, 0), Vector3(0, 0, 1),  Vector3(0, 1, 0)]
		var row_idx = [byte & 3, (byte >> 2) & 3]
		# 3rd index is whatever column is not used in 1st and 2nd
		row_idx.append(3 ^ (row_idx[0] | row_idx[1]))
		var rows = []
		for i in row_idx:
			rows.append(vectors[i])
		var signs = [
			1 if (byte >> 4) & 1 else -1,
			1 if (byte >> 5) & -1 else 1,
			1 if (byte >> 6) & -1 else 1
		]
		# swap rows due to XZY order?
		var result := Basis(
			rows[0] * signs[0],
			rows[2] * signs[2],
			rows[1] * signs[1]
		);
		print('rot_to_basis %s > %s > %s > %s' % [row_idx, rows, signs, result])
		return result

class MVModel extends RefCounted:
	var id: int
	var size: Vector3
	var vox: VoxData

func time(desc: String):
	if TIME_DBG:
		var old_time = _time
		_time = Time.get_ticks_msec()
		print('%s %s ms' % [desc, _time - old_time])

#Gets called when pressing a file gets imported / reimported
func load_vox( source_path, options={mesh_flags=0}, platforms=null, gen_files=null, old_mesh: ArrayMesh = null ):
	if !"mesh_flags" in options:
		# allow user to specify BitField[Mesh.ArrayFormat] flags like ARRAY_FLAG_USE_8_BONE_WEIGHTS
		options.mesh_flags = 0
	print_debug('Import %s' % [source_path])
	_time = Time.get_ticks_msec()
	var start_time = _time
	var CHUNK_DBG = false
	var MESH_DBG = false
	var BONE_DBG = false

	var file = FileAccess.open( source_path, FileAccess.READ )
	if !file:
		return FileAccess.get_open_error()
	var bones_file = FileAccess.open( "%s.bones" % [source_path], FileAccess.READ | FileAccess.COMPRESSION_ZSTD)
	if !bones_file:
		var err := FileAccess.get_open_error()
		if err != ERR_FILE_NOT_FOUND:
			printerr("Unable to open bones file %s.bones: %s" % [source_path, err])
			return null

	##################
	#  Import Voxels #
	##################
	var colors = null
	var data = []
	var tfm := {}
	var nodes := {}
	var groups := {}
	var shapes := {}
	var models := []
	var graph: MVTransformNode = null
	#var derp = PoolByteArray(file.get_8()).get
	var magic = PackedByteArray([file.get_8(),file.get_8(),file.get_8(),file.get_8()]).get_string_from_ascii()

	var version = file.get_32()
	# a MagicaVoxel .vox file starts with a 'magic' 4 character 'VOX ' identifier
	if magic == "VOX ":
		var size := Vector3()
		var names = {}
		var chunkNum = 0

		while file.get_position() < file.get_length():
			# each chunk has an ID, size and child chunks

			var chunk = MVChunk.new()
			chunk.init(file)
			var chunkName = chunk.id
			# there are only a few chunks we care about, and they are SIZE, XYZI, TRNG?, RGBA
			if chunkName == "SIZE":
				size.x = file.get_32()
				# y is up in vox
				size.z = file.get_32()
				# z is backward in vox
				size.y = file.get_32()
				file.get_buffer(chunk.size - 4 * 3)
			elif chunkName == "XYZI":
				# XYZI contains n voxels
				var numVoxels = file.get_32()
				var chunkData = {'data': [], 'vox': VoxData.new(size), 'numVoxels': numVoxels}
				data.append(chunkData)

				for i in range(0,numVoxels):
					var mvc = MVVoxels.new()
					mvc.init(file)
					mvc.chunkNum = chunkNum
					chunkData.data.append(mvc)
					chunkData.vox.set_vox(mvc)
				var model = MVModel.new()
				model.vox = chunkData.vox
				model.size = size
				model.id = len(models)
				models.append(model)
			elif chunkName == "RGBA":
				colors = []

				for i in range(0,256):
					var r = float(file.get_8() / 255.0)
					var g = float(file.get_8() / 255.0)
					var b = float(file.get_8() / 255.0)
					var a = float(file.get_8() / 255.0)

					colors.append(Color(r,g,b,a))
			elif chunkName == "nTRN":
				var tfmNode = MVTransformNode.new()
				tfmNode.init(file)
				if CHUNK_DBG:
					print('nTRN {0}'.format(tfmNode.frames).left(1000))
				if '_name' in tfmNode.attr:
					names[tfmNode.node_id] = tfmNode.attr._name
				tfm[tfmNode.node_id] = tfmNode
				nodes[tfmNode.node_id] = tfmNode
			elif chunkName == "nGRP":
				var grp = MVGroupNode.new()
				grp.init(file)
				groups[grp.node_id] = grp
				nodes[grp.node_id] = grp
			elif chunkName == "nSHP":
				var shp = MVShapeNode.new()
				shp.init(file)
				shapes[shp.node_id] = shp
				nodes[shp.node_id] = shp
			else:
				var buff = file.get_buffer(chunk.size)  # read any excess bytes
				if !(chunkName in ['MATL', 'rOBJ']) and chunkName and CHUNK_DBG:
					print('Unknown chunk: %s with %d children (%db)' % [chunkName, chunk.child_count, chunk.size])
					print('{0}'.format([buff]))
			if file.get_position() < file.get_length() && file.get_position() != chunk.position + chunk.size:
				var diff = chunk.position + chunk.size - file.get_position()
				if CHUNK_DBG:
					print('file position is wrong reading %s %d != %d + %d (%d), skip %d bytes' % [chunkName, file.get_position(), chunk.position, chunk.size, chunk.position + chunk.size, diff])
				var buff = file.get_buffer(diff)
				if CHUNK_DBG:
					# buff might have leading 0
					#buff = buff.subarray(1, buff.size()-1)
					print('{0} {1}'.format([buff, buff.get_string_from_ascii()]))
				assert(diff > 0)
			chunkNum += 1
		if data.size() == 0: return data #failed to read any valid voxel data


		# now push the voxel data into our voxel chunk structure
		for chunk in data:
			for i in range(0, chunk.data.size()):
				var d = chunk.data[i]
				# use the voxColors array by default, or overrideColor if it is available
				if colors == null:
					d.color = Color('#%06x' % voxColors[d.color_idx - 1])
				else:
					d.color = colors[d.color_idx-1]

	file.close()
	time('%s read chunks' % [source_path])

	if len(models) > 1:
		printerr('Multiple models not supported')


	##################
	#   Create Mesh  #
	##################
	var transform := Transform3D()
	var auto_center = 'origin' in options && options.origin != 1
	if auto_center:
		# Calculate aabb for centering offset
		# combine aabb from each voxel chunk
		var s_x = 1000
		var m_x = -1000
		var s_z = 1000
		var m_z = -1000
		var s_y = 1000
		var m_y = -1000
		# todo: transform using transformnodes above?
		for chunk in data:
			var v = chunk.vox
			if v.aabb_start_x < s_x:
				s_x = v.aabb_start_x
			if v.aabb_end_x > m_x:
				m_x = v.aabb_end_x
			if v.aabb_start_z < s_z:
				s_z = v.aabb_start_z
			if v.aabb_end_z > m_z:
				m_z = v.aabb_end_z
			if v.aabb_start_y < s_y:
				s_y = v.aabb_start_y
			if v.aabb_end_y > m_y:
				m_y = v.aabb_end_y
		if MESH_DBG:
			print('x:%s..%s y:%s..%s, z:%s..%s' % [s_x, m_x, s_y, m_y, s_z, m_z])

		# offset so the bottom is at 0
		var y_dif = m_y - s_y
		var y_half = float(y_dif) * 0.5
		transform.origin = Vector3(0, ceil(y_half), 0)
	else:
		var revelant_transforms = find_relevant_transforms(tfm[0], tfm, nodes, groups, shapes, models, 0)
		for t in revelant_transforms:
			transform *= Transform3D(t.basis, Vector3()) * Transform3D(Basis(), t.origin)

	time('set origin')
	# Create the mesh
	var root_scale := float(options.root_scale) if 'root_scale' in options else 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_POINTS)
	for chunk in data:
		var voxelData = chunk.vox
		var smoothing = options.smoothing
		var max_smoothing = ceil(smoothing)
		for voxel in chunk.vox.voxels():
			if !voxel:
				return
			var normal = Vector3(0, 0, 0)
			if not above(voxel,voxelData): normal += NORMALS.up
			if not below(voxel,voxelData): normal += NORMALS.down
			if not onleft(voxel,voxelData): normal += NORMALS.left
			if not onright(voxel,voxelData): normal += NORMALS.right
			if not infront(voxel,voxelData): normal += NORMALS.front
			if not behind(voxel,voxelData): normal += NORMALS.back
			voxel.normal = normal

		time('chunk %s normals' % [chunk.data[0].chunkNum])
		var directions := PackedVector3Array([Vector3.FORWARD, Vector3.RIGHT, Vector3.UP])
		if smoothing > 0:
			# pass1, collect primary axes neighbour smoothing levels..
			for v in chunk.vox.voxels():
				if v:
					var r = Vector3()
					for s_i in range(-max_smoothing, max_smoothing + 1):
						var fraction = max(0, 1 - float(abs(s_i)) / float(smoothing + 1))
						for d in directions:
							var voxel = chunk.vox.get_vox(s_i * d + v.pos)
							if voxel:
								r += voxel.normal * fraction
					v.neighbour_normals = r
			# pass2, collect smoothed neighbour values
			for v in chunk.vox.voxels():
				if v:
					var r = Vector3()
					for s_i in range(-max_smoothing, max_smoothing + 1):
						var fraction = max(0, 1 - float(abs(s_i)) / float(smoothing + 1))
						for d in directions:
							var voxel = chunk.vox.get_vox(s_i * d + v.pos)
							if voxel:
								r += voxel.neighbour_normals * fraction
					v.normal = r

		time('chunk %s normal smoothing' % [chunk.data[0].chunkNum])
		var b = 0
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		if bones_file:
			var bones_len := bones_file.get_32()
			bones = bytes_to_var(bones_file.get_buffer(bones_len))
			var weights_len := bones_file.get_32()
			weights = bytes_to_var(bones_file.get_buffer(weights_len))

		var max_bone := 0
		var bone_colors := PackedColorArray()
		if 'copy_bones_to_uv' in options && options.copy_bones_to_uv:
			for bone_id in bones:
				max_bone = bone_id if bone_id > max_bone else max_bone
			bone_colors = _gen_colors(max_bone)
		if BONE_DBG && (len(bones) || len(weights)):
			print('bones: %s weights: %s %s %s' % [len(bones), len(weights), bones.slice(0, 10), weights.slice(0, 10)])
		if MESH_DBG:
			print('voxels: %s' % [len(chunk.data)])
		var weights_sz = 8 if options.mesh_flags & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
		assert(weights_sz == 4, "ARRAY_FLAG_USE_8_BONE_WEIGHTS not yet supported")
		var center = Transform3D(Basis(), -chunk.vox.center())
		var center_tfm = transform * center

		for voxel in chunk.data:
			st.set_color(voxel.color)
			var normal = voxel.normal
			normal = normal.normalized()
			st.set_normal(normal)

			if bones && weights && len(bones) >= b + weights_sz && len(weights) >= b + weights_sz:
				if 'copy_bones_to_uv' in options && options.copy_bones_to_uv:
					var bc := Color()
					for i in 4:
						bc += bone_colors[bones[b + i] % len(bone_colors)] * weights[b + i]
					st.set_uv(Vector2(bc.r, bc.g))
					st.set_uv2(Vector2(bc.b, 1.0))
				st.set_bones(PackedInt32Array([bones[b], bones[b + 1], bones[b + 2], bones[b + 3]]))
				st.set_weights([weights[b], weights[b + 1], weights[b + 2], weights[b + 3]])
				b += weights_sz

			#st.add_tangent(normal.normalized())
			st.add_vertex((center_tfm * (voxel.pos)) * root_scale)
			"""
			for tri in to_draw:
				st.add_vertex( (tri*0.5)+voxel.pos+dif)
			"""
		var sz = chunk.vox.size
		time('chunk %s geometry %s/%s %s (dict:%s) %s..%s' % [
			chunk.data[0].chunkNum, chunk.numVoxels, sz.volume(), sz, chunk.vox.use_dict,
			[chunk.vox.aabb_start_x, chunk.vox.aabb_start_y, chunk.vox.aabb_start_z],
			[chunk.vox.aabb_end_x, chunk.vox.aabb_end_y, chunk.vox.aabb_end_z]
			])
		if TIME_DBG:
			var USEC_TO_MSEC = 0.001
			var t := PackedInt64Array([0, 0, 0, 0, 0, 0])
			for v in chunk.vox:
				for i in range(len(t)):
					t[i] += v.t[i]
			print('t=%s' % [[
				t[0] * USEC_TO_MSEC, t[1] * USEC_TO_MSEC, t[2] * USEC_TO_MSEC, t[3] * USEC_TO_MSEC
			]])
	#st.generate_normals()

	var shader_path = self.get_script().get_path().replace('plugin.gd', 'points.gdshader')
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter('albedo', Color(1, 1, 1))
	material.set_shader_parameter('root_scale', root_scale)
	#material.set_flag(material.FLAG_USE_COLOR_ARRAY,true)
	st.set_material(material)
	var mesh: ArrayMesh
	time('set material')
	if old_mesh:
		old_mesh.clear_surfaces()
		mesh = st.commit(old_mesh, options.mesh_flags)
	else:
		mesh = st.commit(null, options.mesh_flags)

	mesh.set_meta('root_scale', root_scale)
	time('commit mesh')
	_time = start_time
	time('total')
	data = null
	return mesh

func _gen_colors(count: int) -> PackedColorArray:
	count = max(count, 4)
	var result := PackedColorArray()
	var h_repeat: float = 3.0
	var h_repeat_half := h_repeat * 0.5
	for i in count:
		var h := _fract(float(i) / float(count) * h_repeat)
		var s: float = 1.0 if count <= 4 else floor(float(i) / float(count) * h_repeat_half) / h_repeat_half * 0.5 + 0.5
		var v: float = floor(float(i) / float(count) * 2.0) / 2.0 * 0.5 + 0.5
		result.append(Color.from_hsv(h, s , v))
	return result

func _fract(v: float) -> float:
	return v - floor(v)

func find_relevant_transforms(root: MVTransformNode, tfm: Dictionary, nodes: Dictionary, groups: Dictionary, shapes: Dictionary, models: Array, model_id: int):
	# shapes indexed by model
	var model_owners := {}
	# nodes indexed by their child node_ids
	var node_owners := {}
	# build node graph
	for s in shapes:
		for m in shapes[s].model_data:
			shapes[s].models.append(models[m.model_id])
			model_owners[m.model_id] = shapes[s]
	for t in tfm:
		tfm[t].child = nodes[tfm[t].child_node_id]
		node_owners[tfm[t].child_node_id] = tfm[t]
	for g in groups:
		for cid in groups[g].child_ids:
			node_owners[cid] = groups[g]
			groups[g].children.append(nodes[cid])
	var result := []
	# walk up the node graph
	var p = model_owners[model_id]
	while p:
		if p is MVTransformNode:
			result.append(p)
		p = node_owners[p.node_id] if p.node_id in node_owners else null
	result.reverse()
	return result



#Data
var voxColors = [
	0x00000000, 0xffffffff, 0xffccffff, 0xff99ffff, 0xff66ffff, 0xff33ffff, 0xff00ffff, 0xffffccff, 0xffccccff, 0xff99ccff, 0xff66ccff, 0xff33ccff, 0xff00ccff, 0xffff99ff, 0xffcc99ff, 0xff9999ff,
	0xff6699ff, 0xff3399ff, 0xff0099ff, 0xffff66ff, 0xffcc66ff, 0xff9966ff, 0xff6666ff, 0xff3366ff, 0xff0066ff, 0xffff33ff, 0xffcc33ff, 0xff9933ff, 0xff6633ff, 0xff3333ff, 0xff0033ff, 0xffff00ff,
	0xffcc00ff, 0xff9900ff, 0xff6600ff, 0xff3300ff, 0xff0000ff, 0xffffffcc, 0xffccffcc, 0xff99ffcc, 0xff66ffcc, 0xff33ffcc, 0xff00ffcc, 0xffffcccc, 0xffcccccc, 0xff99cccc, 0xff66cccc, 0xff33cccc,
	0xff00cccc, 0xffff99cc, 0xffcc99cc, 0xff9999cc, 0xff6699cc, 0xff3399cc, 0xff0099cc, 0xffff66cc, 0xffcc66cc, 0xff9966cc, 0xff6666cc, 0xff3366cc, 0xff0066cc, 0xffff33cc, 0xffcc33cc, 0xff9933cc,
	0xff6633cc, 0xff3333cc, 0xff0033cc, 0xffff00cc, 0xffcc00cc, 0xff9900cc, 0xff6600cc, 0xff3300cc, 0xff0000cc, 0xffffff99, 0xffccff99, 0xff99ff99, 0xff66ff99, 0xff33ff99, 0xff00ff99, 0xffffcc99,
	0xffcccc99, 0xff99cc99, 0xff66cc99, 0xff33cc99, 0xff00cc99, 0xffff9999, 0xffcc9999, 0xff999999, 0xff669999, 0xff339999, 0xff009999, 0xffff6699, 0xffcc6699, 0xff996699, 0xff666699, 0xff336699,
	0xff006699, 0xffff3399, 0xffcc3399, 0xff993399, 0xff663399, 0xff333399, 0xff003399, 0xffff0099, 0xffcc0099, 0xff990099, 0xff660099, 0xff330099, 0xff000099, 0xffffff66, 0xffccff66, 0xff99ff66,
	0xff66ff66, 0xff33ff66, 0xff00ff66, 0xffffcc66, 0xffcccc66, 0xff99cc66, 0xff66cc66, 0xff33cc66, 0xff00cc66, 0xffff9966, 0xffcc9966, 0xff999966, 0xff669966, 0xff339966, 0xff009966, 0xffff6666,
	0xffcc6666, 0xff996666, 0xff666666, 0xff336666, 0xff006666, 0xffff3366, 0xffcc3366, 0xff993366, 0xff663366, 0xff333366, 0xff003366, 0xffff0066, 0xffcc0066, 0xff990066, 0xff660066, 0xff330066,
	0xff000066, 0xffffff33, 0xffccff33, 0xff99ff33, 0xff66ff33, 0xff33ff33, 0xff00ff33, 0xffffcc33, 0xffcccc33, 0xff99cc33, 0xff66cc33, 0xff33cc33, 0xff00cc33, 0xffff9933, 0xffcc9933, 0xff999933,
	0xff669933, 0xff339933, 0xff009933, 0xffff6633, 0xffcc6633, 0xff996633, 0xff666633, 0xff336633, 0xff006633, 0xffff3333, 0xffcc3333, 0xff993333, 0xff663333, 0xff333333, 0xff003333, 0xffff0033,
	0xffcc0033, 0xff990033, 0xff660033, 0xff330033, 0xff000033, 0xffffff00, 0xffccff00, 0xff99ff00, 0xff66ff00, 0xff33ff00, 0xff00ff00, 0xffffcc00, 0xffcccc00, 0xff99cc00, 0xff66cc00, 0xff33cc00,
	0xff00cc00, 0xffff9900, 0xffcc9900, 0xff999900, 0xff669900, 0xff339900, 0xff009900, 0xffff6600, 0xffcc6600, 0xff996600, 0xff666600, 0xff336600, 0xff006600, 0xffff3300, 0xffcc3300, 0xff993300,
	0xff663300, 0xff333300, 0xff003300, 0xffff0000, 0xffcc0000, 0xff990000, 0xff660000, 0xff330000, 0xff0000ee, 0xff0000dd, 0xff0000bb, 0xff0000aa, 0xff000088, 0xff000077, 0xff000055, 0xff000044,
	0xff000022, 0xff000011, 0xff00ee00, 0xff00dd00, 0xff00bb00, 0xff00aa00, 0xff008800, 0xff007700, 0xff005500, 0xff004400, 0xff002200, 0xff001100, 0xffee0000, 0xffdd0000, 0xffbb0000, 0xffaa0000,
	0xff880000, 0xff770000, 0xff550000, 0xff440000, 0xff220000, 0xff110000, 0xffeeeeee, 0xffdddddd, 0xffbbbbbb, 0xffaaaaaa, 0xff888888, 0xff777777, 0xff555555, 0xff444444, 0xff222222, 0xff111111
	]

var top = [
	Vector3( 1.0000, 1.0000, 1.0000),
	Vector3(-1.0000, 1.0000, 1.0000),
	Vector3(-1.0000, 1.0000,-1.0000),

	Vector3(-1.0000, 1.0000,-1.0000),
	Vector3( 1.0000, 1.0000,-1.0000),
	Vector3( 1.0000, 1.0000, 1.0000),
]

var down = [
	Vector3(-1.0000,-1.0000,-1.0000),
	Vector3(-1.0000,-1.0000, 1.0000),
	Vector3( 1.0000,-1.0000, 1.0000),

	Vector3( 1.0000, -1.0000, 1.0000),
	Vector3( 1.0000, -1.0000,-1.0000),
	Vector3(-1.0000, -1.0000,-1.0000),
]

var front = [
	Vector3(-1.0000, 1.0000, 1.0000),
	Vector3( 1.0000, 1.0000, 1.0000),
	Vector3( 1.0000,-1.0000, 1.0000),

	Vector3( 1.0000,-1.0000, 1.0000),
	Vector3(-1.0000,-1.0000, 1.0000),
	Vector3(-1.0000, 1.0000, 1.0000),
]

var back = [
	Vector3( 1.0000,-1.0000,-1.0000),
	Vector3( 1.0000, 1.0000,-1.0000),
	Vector3(-1.0000, 1.0000,-1.0000),

	Vector3(-1.0000, 1.0000,-1.0000),
	Vector3(-1.0000,-1.0000,-1.0000),
	Vector3( 1.0000,-1.0000,-1.0000)
]

var left = [
	Vector3(-1.0000, 1.0000, 1.0000),
	Vector3(-1.0000,-1.0000, 1.0000),
	Vector3(-1.0000,-1.0000,-1.0000),

	Vector3(-1.0000,-1.0000,-1.0000),
	Vector3(-1.0000, 1.0000,-1.0000),
	Vector3(-1.0000, 1.0000, 1.0000),
]

var right = [
	Vector3( 1.0000, 1.0000, 1.0000),
	Vector3( 1.0000, 1.0000,-1.0000),
	Vector3( 1.0000,-1.0000,-1.0000),

	Vector3( 1.0000,-1.0000,-1.0000),
	Vector3( 1.0000,-1.0000, 1.0000),
	Vector3( 1.0000, 1.0000, 1.0000),
]

var NORMALS = {
	'up': Vector3(0, 1, 0),
	'down': Vector3(0, -1, 0),
	'left': Vector3(-1, 0, 0),
	'right': Vector3(1, 0, 0),
	'front': Vector3(0, 0, 1),
	'back': Vector3(0, 0, -1)
}

#Some static functions
func above(vox, v): return v.get_vox(vox.pos + Vector3(0, 1, 0))
func below(vox, v): return v.get_vox(vox.pos + Vector3(0, -1, 0))
func onleft(vox, v): return v.get_vox(vox.pos + Vector3(-1, 0, 0))
func onright(vox, v): return v.get_vox(vox.pos + Vector3(1, 0, 0))
func infront(vox, v): return v.get_vox(vox.pos + Vector3(0, 0, 1))
func behind(vox, v): return v.get_vox(vox.pos + Vector3(0, 0, -1))
