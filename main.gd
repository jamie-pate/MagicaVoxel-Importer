extends Node3D

var bench_count := 0
var bench_i := 0
var bench_depth := -1.0
var next_bench_count := 2
var visible_on_screen := 0

func _renderer():
	return "%s: %s" % [
		RenderingServer.get_video_adapter_name(),
		"Vulkan" if RenderingServer.get_rendering_device() else "OpenGL"
	]

func _ready():
	$Label.text = _renderer()


func _on_control_pressed() -> void:
	_benchmark()


func _benchmark():
	$Timer.start()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene := load("res://testbig.tscn")
	bench_depth += 1.0
	for i in next_bench_count:
		var node: Node3D = scene.instantiate()
		var offset := (next_bench_count * 0.5) - float(i) - 0.5
		node.position = Vector3.DOWN * 0.5
		node.position += Vector3.LEFT * offset
		node.position += Vector3.FORWARD * bench_depth
		node.position += Vector3.UP * (bench_i * bench_i) * 0.25
		var n := VisibleOnScreenNotifier3D.new()
		node.add_child(n)
		n.aabb = AABB(Vector3.ONE * -0.1, Vector3.ONE * 0.2)
		n.screen_entered.connect(func(): visible_on_screen += 1)
		n.screen_exited.connect(func(): visible_on_screen -= 1)
		add_child(node)

	bench_i += 1
	bench_depth += next_bench_count / 5
	bench_count += next_bench_count
	next_bench_count += next_bench_count


func _on_timer_timeout() -> void:
	$Label.text = "%sfps %s\nbench %s: %s/%s on screen %s prim" % [
		Engine.get_frames_per_second(),
		_renderer(),
		bench_i,
		visible_on_screen,
		bench_count,
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	]


func _on_xr_button_pressed(tracker: String, button: String) -> void:
	_benchmark()
