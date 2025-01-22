@tool
extends EditorPlugin

const BoneRig4 = preload('./bone_rig4.gd')
const VoxelImport = preload('./voxel_import.gd')
const BR_COLLECT_MENU_ITEM := "Bone Rig: Collect All"

var import_plugin
var control

func _enter_tree():
	#Add import plugin
	import_plugin = ImportPlugin.new()
	add_import_plugin(import_plugin)
	add_tool_menu_item(BR_COLLECT_MENU_ITEM, _collect_all_bones)

func _exit_tree():
	#remove plugin
	remove_import_plugin(import_plugin)
	remove_tool_menu_item(BR_COLLECT_MENU_ITEM)
	import_plugin = null


func _collect_bones(scene_path: String) -> Array[String]:
	var st := get_tree()

	var root := load(scene_path).instantiate() as Node
	var result: Array[String]
	st.root.add_child(root)

	for node in st.get_nodes_in_group("MVBoneRig") as Array[BoneRig4]:
		var mi := node.get_node(node.mesh_path) as MeshInstance3D
		if mi && mi.mesh:
			var rp = mi.mesh.resource_path
			if rp.ends_with(".vox"):
				result.append(rp)
				print("Collecting for %s" % [rp])
				node.auto_reimport = false
				await node.collect_bones_once(true)
	root.free()
	return result

func _collect_all_bones(fs_dir: EditorFileSystemDirectory = null) -> Array[String]:
	var fs: EditorFileSystem
	if !fs_dir:
		fs = EditorInterface.get_resource_filesystem()
		fs_dir = fs.get_filesystem()
	var result: Array[String]
	for i in fs_dir.get_file_count():
		var deps = ResourceLoader.get_dependencies(fs_dir.get_file_path(i))
		if len(deps):
			for d in deps:
				if d.get_file() == "bone_rig4.gd":
					result.append_array(await _collect_bones(fs_dir.get_file_path(i)))
					break
	for i in fs_dir.get_subdir_count():
		result.append_array(await _collect_all_bones(fs_dir.get_subdir(i)))
	if fs && len(result):
		print("Reimporting %s files" % [len(result)])
		fs.reimport_files(result)
	return result

##############################################
#                Import Plugin               #
##############################################


class ImportPlugin extends EditorImportPlugin:
	#The Name shown in the Plugin Menu
	func _get_importer_name():
		return 'MagicaVoxel-Importer'

	#The Name shown under 'Import As' in the Import menu
	func _get_visible_name():
		return "MagicaVoxels as Points"

	#The File extensions that this Plugin can import. Those will then show up in the Filesystem
	func _get_recognized_extensions():
		return ['vox']

	#The Resource Type it creates. Im still not sure what exactly this does
	func _get_resource_type():
		return "Mesh"

	#The extenison the imported file will have
	func _get_save_extension() -> String:
		return 'mesh'

	#Returns an Array or Dictionaries that declare which options exist.
	#Those options will show up under 'Import As'
	func _get_import_options(_path, _preset_index):
		var options: Array[Dictionary] = [
			{'name': 'root_scale', 'default_value': 1.0},
			{'name': 'origin', 'default_value': 0,
				'property_hint': PROPERTY_HINT_ENUM,
				'hint_string': 'Auto Center,Use Transform3D'},
			{'name': 'smoothing', 'default_value': 1.0,
				'property_hint': PROPERTY_HINT_RANGE, 'hint_string': '0.0,10.0,0.1'},
			{'name': 'copy_bones_to_uv', 'default_value': false,
				'property_hint': PROPERTY_HINT_ENUM,
				'hint_string': 'Off,Debug'
			},
			{
				'name': 'wall_thickness',
				'default_value': 2,
				'property_hint': PROPERTY_HINT_RANGE,
				'hint_string': '0,10,1,or_greater'
			}
		]
		return options

	#The Number of presets
	func _get_preset_count():
		return 0

	#The Name of the preset.
	func _get_preset_name(preset):
		return "Default"

	func _get_priority():
		return 1

	func _get_import_order():
		return 0

	func _get_option_visibility(path, option_name, options):
		return true

	func _import(source_path, save_path, options, platforms, gen_files):
		var vi = VoxelImport.new()
		var mesh: ArrayMesh = vi.load_vox(source_path, options, platforms, gen_files)

		var full_path = "%s.%s" % [save_path, _get_save_extension()]
		# https://github.com/godotengine/godot/issues/90461
		var mutex_bug = true
		if mutex_bug && OS.get_main_thread_id() != OS.get_thread_caller_id():
			print("saving %s deferred" % [full_path])
			call_deferred("_save", mesh, full_path)
			return OK
		return _save(mesh, full_path)

	func _save(mesh, full_path):
		print("saved to ", full_path)
		return ResourceSaver.save(mesh, full_path)
