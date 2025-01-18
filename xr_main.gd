extends Node3D

signal button_pressed(tracker: String, button: String)

@export var auto_enabled := false
@export var force_enabled := false

func _ready():
	if !auto_enabled:
		return
	var XRServer = Engine.get_singleton("XRServer")
	if !XRServer:
		return
	var interface: XRInterface = XRServer.find_interface("OpenXR")
	if !interface.is_initialized():
		if interface.initialize():
			print("Initialized OpenXR")
		elif force_enabled:
			interface = XRServer.find_interface("Native mobile")
			if interface && !interface.is_initialized() && interface.initialize():
				interface.eye_height = 0.1
				print("Initialized Native Mobile XR")
			else:
				printerr("Failed to initialize XR")
				return
	#interface.start_passthrough()
	get_viewport().transparent_bg = true
	get_viewport().use_xr = true


func _on_xr_controller_left_hand_button_pressed(name: String) -> void:
	button_pressed.emit("left_hand", name)


func _on_xr_controller_right_hand_button_pressed(name: String) -> void:
	button_pressed.emit("right_hand", name)


func _on_area_3d_area_entered(area: Area3D) -> void:
	button_pressed.emit("left_hand", "clap")
