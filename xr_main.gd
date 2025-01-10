extends Node3D

func _ready():
	var interface := XRServer.find_interface("OpenXR")
	if !interface.is_initialized():
		interface.initialize()
		#interface.start_passthrough()
	get_viewport().transparent_bg = true
	get_viewport().use_xr = true
