@tool
extends EditorPlugin

const VoxelImport = preload('./voxel_import.gd')
var import_plugin
var control

func _enter_tree():
	#Add import plugin
	import_plugin = ImportPlugin.new()
	add_import_plugin(import_plugin)

func _exit_tree():
	#remove plugin
	remove_import_plugin(import_plugin)
	import_plugin = null


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
			}
		]
		#options.append( { "name":"Pack in scene", "default_value":false } )
		#options.append( { "name":"target_path", "default_value":"" } )
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

	func _import( source_path, save_path, options, platforms, gen_files ):
		var old_mesh: ArrayMesh
		if FileAccess.file_exists(save_path):
			old_mesh = ResourceLoader.load(save_path)
		var vi = VoxelImport.new()
		var mesh: ArrayMesh = vi.load_vox(source_path, options, platforms, gen_files, old_mesh)

		var full_path = "%s.%s" % [save_path, _get_save_extension()]
		# https://github.com/godotengine/godot/issues/90461
		var mutex_bug = true
		if mutex_bug:
			call_deferred("_save", mesh, full_path)
			return OK
		return _save(mesh, full_path)

	func _save(mesh, full_path):
		return ResourceSaver.save(mesh, full_path, ResourceSaver.FLAG_CHANGE_PATH)
