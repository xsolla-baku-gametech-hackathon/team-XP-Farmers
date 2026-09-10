extends SceneTree
## Optional visual check; run with a real renderer, not --headless.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var demo = load("res://demo/main.tscn").instantiate()
	root.add_child(demo)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	root.get_texture().get_image().save_png("res://.artifacts/demo-off.png")
	demo.controller.set_enabled(true)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.artifacts/demo-on.png")
	demo.set_menu_open(true)
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.artifacts/demo-settings.png")
	demo.set_menu_open(false)
	demo.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit()

