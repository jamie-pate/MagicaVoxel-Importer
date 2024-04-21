@tool
extends Area3D

const BoneRig4 = preload("./bone_rig4.gd")

# todo: plugin menu?
## Click here to upgrade to the new layout
@export var upgrade_3to4 := false: set = _set_upgrade_3to4

# todo: plugin menu?
# Keep these values so we can copy them to the new node
@export var auto_reimport := true

# magic property that will update the prefix on ALL rig children!
@export var bone_prefix: String
@export var blend_factor: float = 1.0
@export_node_path("MeshInstance3D") var mesh_path: NodePath
@export_node_path("Skeleton3D") var skeleton_path: NodePath

var _new_prefix = null
var _old_prefix = null
var _collecting_bones := false


func _shape_name_to_bone_name(value: String):
	var parts = value.rsplit('#', 1)
	return parts[0] if len(parts) else ''

func _set_upgrade_3to4(value):
	# Click here to upgrade to the new version
	if !value || !Engine.is_editor_hint() || !is_inside_tree():
		return
	var upgraded = Node3D.new()
	upgraded.name = "%s4" % [name]
	var p := get_parent()
	upgraded.script = BoneRig4
	add_sibling(upgraded)
	upgraded.owner = owner
	var usage_ok = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE
	var usage_never = PROPERTY_USAGE_NEVER_DUPLICATE
	for prop in get_property_list():
		if prop.usage & usage_ok && !prop.usage & usage_never && prop.name in upgraded:
			upgraded[prop.name] = self[prop.name]
	var bones := {}
	for s in get_children():
		var bone_name = _shape_name_to_bone_name(s.name)
		if !bone_name in bones:
			bones[bone_name] = []
		bones[bone_name].append(s)
	for bone_name in bones:
		var area := Area3D.new()
		area.name = bone_name
		area.collision_mask = 0
		area.monitorable = false
		area.monitoring = false
		upgraded.add_child(area)
		area.owner = owner
		for s in bones[bone_name]:
			var new_s = s.duplicate()
			assert(new_s.transform == s.transform)
			var parts = s.name.split("#", true, 1)
			new_s.name = parts[1] if len(parts) > 1 else "Shape"
			area.add_child(new_s)
			new_s.owner = owner
	print("Upgraded: %s" % [upgraded])
