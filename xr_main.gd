extends Node3D

func _ready():
	var interface := XRServer.find_interface("OpenXR")
	if !interface.is_initialized():
		if interface.initialize():
			print("Initialized OpenXR")
		else:
			interface = XRServer.find_interface("Native mobile")
			if interface && !interface.is_initialized() && interface.initialize():
				print("Initialized Native Mobile XR")
			else:
				printerr("Failed to initialize XR")

		#interface.start_passthrough()
	get_viewport().transparent_bg = true
	get_viewport().use_xr = true
