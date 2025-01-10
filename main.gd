extends Node3D

func _ready():
	$Label.text = "Vulkan" if RenderingServer.get_rendering_device() else "OpenGL"
