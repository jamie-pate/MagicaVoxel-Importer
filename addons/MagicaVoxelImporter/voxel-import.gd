extends Reference
const shader = preload('./points.shader')

class MV:
	# revive a string from the stream
	func mv_str(file):
		var size = file.get_32()
		var buff = file.get_buffer(size)
		# assume utf8? not sure, but should be safe
		return buff.get_string_from_utf8()

	# revive a dict from the stream
	func mv_dict(file, unpack):
		var size = file.get_32()
		var result = {}
		for i in size:
			var key = mv_str(file)
			if key in unpack:
				match unpack[key]:
					's':
						result[key] = mv_str(file)
					'int8':
						result[key] = file.get_8()
					'int32':
						result[key] = file.get_32()
					'int32x3':
						result[key] = Vector3(file.get_8(), file.get_8(), file.get_8())
					_:
						print('Couldn\'t unpack key %s' % key)
						assert(false)
			else:
				print('bogus key from mv_str: %s' % key)
		return result

class MVChunk:
	var id
	var size
	var child_count
	var position
	var header_position

	func init(file):
		header_position = file.get_position()
		id = PoolByteArray([file.get_8(),file.get_8(),file.get_8(),file.get_8()]).get_string_from_ascii() #char[] chunkId
		size = file.get_32()
		child_count = file.get_32()
		position = file.get_position()
		#print('id:%s sz:%d cc:%d' % [id, size, child_count])

class MVVoxels:
	var pos = Vector3(0,0,0)
	var color
	# contain which chunk we are in so we can find it's name later?
	var chunkNum = -1
	var bone
	func init(file):
		pos.x = file.get_8()
		pos.z = -file.get_8()
		pos.y = file.get_8()

		color = file.get_8()

class MVTransformNode extends MV:
	var node_id
	var attr
	var child_node_id
	var reserved_id
	var layer_id
	var frame_count
	var frames

	func init(file):
		node_id = file.get_32()
		attr = mv_dict(file, {
			'_name': 's',
			# NOTE: not sure if this conversion for `_hidden`
			# is correct since the docs just say 1/0
			# '_hidden': 'int32',
		})
		child_node_id = file.get_32()
		reserved_id = file.get_32()
		layer_id = file.get_32()
		frame_count = file.get_32()
		frames = []
		assert(frame_count == 1)
		for i in frame_count:
			frames.append(mv_dict(file, {'_r': 'int8', '_t': 'int32x3'}))

func vox_arr():
	#Initialize and populate voxel array
	var voxelArray = []
	for x in range(0,128):
		voxelArray.append([])
		for y in range(0,128):
			voxelArray[x].append([])
			voxelArray[x][y].resize(128)
	return voxelArray

#Gets called when pressing a file gets imported / reimported
func load_vox( source_path, options={bone_map=''}, platforms=null, gen_files=null, old_mesh: ArrayMesh = null ):

	var CHUNK_DBG = false
	var MESH_DBG = false
	var file = File.new()
	var error = file.open( source_path, File.READ )
	if error != OK:
		if file.is_open(): file.close()
		return error

	##################
	#  Import Voxels #
	##################
	var colors = null
	var data = []
	#var derp = PoolByteArray(file.get_8()).get
	var magic = PoolByteArray([file.get_8(),file.get_8(),file.get_8(),file.get_8()]).get_string_from_ascii()

	var version = file.get_32()

	# a MagicaVoxel .vox file starts with a 'magic' 4 character 'VOX ' identifier
	if magic == "VOX ":
		var sizex = 0
		var sizey = 0
		var sizez = 0
		var names = {}
		var chunkNum = 0

		while file.get_position() < file.get_len():
			# each chunk has an ID, size and child chunks

			var chunk = MVChunk.new()
			chunk.init(file)
			var chunkName = chunk.id
			# there are only a few chunks we care about, and they are SIZE, XYZI, TRNG?, RGBA
			if chunkName == "SIZE":
				sizex = file.get_32()
				sizey = file.get_32()
				sizez = file.get_32()

				file.get_buffer(chunk.size - 4 * 3)
			elif chunkName == "XYZI":
				# XYZI contains n voxels
				var numVoxels = file.get_32()
				var chunkData = {'data': [], 'vox': vox_arr()}
				data.append(chunkData)
				# each voxel has x, y, z and color index values
				for i in range(0,numVoxels):
					var mvc = MVVoxels.new()
					mvc.init(file)
					mvc.chunkNum = chunkNum
					chunkData.data.append(mvc)
					chunkData.vox[mvc.pos.x][mvc.pos.y][mvc.pos.z] = mvc
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
			else:
				var buff = file.get_buffer(chunk.size)  # read any excess bytes
				if !(chunkName in ['MATL', 'rOBJ']) and chunkName and CHUNK_DBG:
					print('Unknown chunk: %s with %d children (%db)' % [chunkName, chunk.child_count, chunk.size])
					print('{0}'.format([buff]))
			if file.get_position() < file.get_len() && file.get_position() != chunk.position + chunk.size:
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

		var bone_map = {}
		for name_id in options.bone_map.split(','):
			var parts = name_id.split('=')
			if len(parts) == 2:
				bone_map[parts[0]] = parts[1]
		# now push the voxel data into our voxel chunk structure
		for chunk in data:
			for i in range(0, chunk.data.size()):
				var d = chunk.data[i]
				# use the voxColors array by default, or overrideColor if it is available
				if colors == null:
					d.color = Color('#%06x' % voxColors[d.color - 1])
				else:
					d.color = colors[d.color-1]
				if d.chunkNum < len(names):
					var bone_name = names[d.chunkNum]
					d.bone = bone_map[bone_name]
	file.close()

	##################
	#   Create Mesh  #
	##################

	#Calculate aabb for centering offset
	var s_x = 1000
	var m_x = -1000
	var s_z = 1000
	var m_z = -1000
	var s_y = 1000
	var m_y = -1000
	# todo: separate aabb per chunk? transform using transformnodes above?
	for chunk in data:
		for d in chunk.data:
			var p = d.pos
			if p.x < s_x: s_x = p.x
			elif p.x > m_x: m_x = p.x
			if p.z < s_z: s_z = p.z
			elif p.z > m_z: m_z = p.z
			# note: not centering on the y axis, but this is used in the next step
			if p.y < s_y: s_y = p.y
			elif p.y > m_y: m_y = p.y
	if MESH_DBG:
		print([s_x, m_x, s_z, m_z, s_y, m_y])
	for chunk in data:
		# create empty 3d arrays as buffers for normal smoothing
		# TODO: really only need 2 buffers
		chunk.normals = [[], [], [], []]
		for n in chunk.normals:
			for x_ in range(m_x - s_x + 1):
				var x = []
				n.append(x)
				for y_ in range(m_y - s_y + 1):
					var y = []
					x.append(y)
					for z_ in range(m_z - s_z + 1):
						y.append(Vector3())

	var x_dif = m_x - s_x
	var z_dif = m_z - s_z
	var dif = Vector3(-s_x-x_dif/2.0,0,-s_z-z_dif/2.0)

	#Create the mesh
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_POINTS)
	for chunk in data:
		var voxelData = chunk.vox
		var n = chunk.normals
		var smoothing = options.smoothing
		var max_smoothing = ceil(smoothing)
		var i = 0
		if smoothing <= 0:
			i = 3
		for voxel in chunk.data:
			var key = Vector3(voxel.pos.x, voxel.pos.y, voxel.pos.z)
			var normal = Vector3(0, 0, 0)
			if not above(voxel,voxelData): normal += NORMALS.up
			if not below(voxel,voxelData): normal += NORMALS.down
			if not onleft(voxel,voxelData): normal += NORMALS.left
			if not onright(voxel,voxelData): normal += NORMALS.right
			if not infront(voxel,voxelData): normal += NORMALS.front
			if not behind(voxel,voxelData): normal += NORMALS.back
			var s = Vector3(s_x, s_y, s_z)
			n[i][voxel.pos.x - s_x][voxel.pos.y - s_y][voxel.pos.z - s_z] = normal
		if smoothing > 0:
			var size = Vector3(m_x - s_x + 1, m_y - s_y + 1, m_z - s_z + 1)
			if MESH_DBG:
				print('%s %s voxels x 3 x %s (%s)' % [size, size.x * size.y * size.z , smoothing * 2 + 1, smoothing])
			for x_idx in range(size.x):
				for y_idx in range(size.y):
					for z_idx in range(size.z):
						var r = Vector3()
						for s_i in range(-max_smoothing, max_smoothing + 1):
							var fraction = 1 - float(abs(s_i)) / float(smoothing + 1)
							if s_i + x_idx >= 0 && s_i + x_idx < size.x:
								r += n[0][x_idx + s_i][y_idx][z_idx] * fraction
						n[1][x_idx][y_idx][z_idx] = r

			for x_idx in range(size.x):
				for y_idx in range(size.y):
					for z_idx in range(size.z):
						var r = Vector3()
						for s_i in range(-max_smoothing, max_smoothing + 1):
							var fraction = 1 - float(abs(s_i)) / float(smoothing + 1)
							if s_i + y_idx >= 0 && s_i + y_idx < size.y:
								r += n[1][x_idx][y_idx + s_i][z_idx] * fraction
						n[2][x_idx][y_idx][z_idx] = r

			for x_idx in range(size.x):
				for y_idx in range(size.y):
					for z_idx in range(size.z):
						var r = Vector3()
						for s_i in range(-max_smoothing, max_smoothing + 1):
							var fraction = 1 - float(abs(s_i)) / float(smoothing + 1)
							if s_i + z_idx >= 0 && s_i + z_idx <size.z:
								r += n[2][x_idx][y_idx][z_idx + s_i] * fraction
						n[3][x_idx][y_idx][z_idx] = r

		for voxel in chunk.data:
			st.add_color(voxel.color)
			var normal = n[3][voxel.pos.x - s_x][voxel.pos.y - s_y][voxel.pos.z - s_z]
			normal = normal.normalized()
			st.add_normal(normal)
			# todo: add multiple bones? weight painted?
			if voxel.bone:
				st.add_bones([voxel.bone, 0, 0, 0])
				st.add_weights([1, 0, 0, 0])
			#st.add_tangent(normal.normalized())
			st.add_vertex(voxel.pos + dif)
			"""
			for tri in to_draw:
				st.add_vertex( (tri*0.5)+voxel.pos+dif)
			"""
	#st.generate_normals()

	var shader_path = self.get_script().get_path().replace('plugin.gd', 'points.shader')
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_param('screen_size', 1024)
	material.set_shader_param('point_size', 20)
	material.set_shader_param('albedo', Color(1, 1, 1))
	#material.set_flag(material.FLAG_USE_COLOR_ARRAY,true)
	st.set_material(material)
	var mesh: ArrayMesh

	if old_mesh:
		old_mesh.surface_remove(0)
		mesh = st.commit(old_mesh)
	else:
		mesh = st.commit()
	return mesh

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

#Some staic functions
func above(cube, array): return array[cube.pos.x][cube.pos.y+1][cube.pos.z]
func below(cube, array): return array[cube.pos.x][cube.pos.y-1][cube.pos.z]
func onleft(cube, array): return array[cube.pos.x-1][cube.pos.y][cube.pos.z]
func onright(cube, array): return array[cube.pos.x+1][cube.pos.y][cube.pos.z]
func infront(cube, array): return array[cube.pos.x][cube.pos.y][cube.pos.z+1]
func behind(cube, array): return array[cube.pos.x][cube.pos.y][cube.pos.z-1]