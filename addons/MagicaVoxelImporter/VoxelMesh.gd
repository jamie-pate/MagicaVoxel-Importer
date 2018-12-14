tool
extends MeshInstance

# class member variables go here, for example:
# var a = 2
# var b = "textvar"
export(float) var point_size setget _set_point_size

func _ready():
	# Called when the node is added to the scene for the first time.
	# Initialization here
	get_tree().connect('screen_resized', self, '_resized')
	if point_size == 0:
		point_size = 24
	_resized()

func _resized():
	var mat = mesh.surface_get_material(0)
	var viewport = get_viewport()
	if viewport:
		var screen_size = viewport.get_size_override() if viewport.is_size_override_enabled() else viewport.size
				
		var size = max(screen_size.x, screen_size.y)
		mat.set_shader_param('screen_size', size)

func _set_point_size(value):
	point_size = value
	call_deferred('_set_point_size_deferred', value)

func _set_point_size_deferred(value):
	var mat = mesh.surface_get_material(0)
	mat.set_shader_param('point_size', value)
	_resized()

#func _process(delta):
#	# Called every frame. Delta is time since last frame.
#	# Update game logic here.
#	pass
