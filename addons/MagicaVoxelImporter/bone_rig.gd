@tool
extends Area3D

const BoneRig4 = preload("./bone_rig4.gd")

# todo: plugin menu?
@export var upgrade_3to4 := false: set = _set_upgrade_3to4

@export var blend_factor: float = 1.0

var _new_prefix = null
var _old_prefix = null
var _collecting_bones := false


func _set_upgrade_3to4(value):
	# Click here to upgrade to the new version
	if !value || !Engine.is_editor_hint():
		return
	var node = Node3D.new()
	node.script = BoneRig4
