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
	demo.services.chat.overlay.append_message("Test fixture", "Twitch / Kick / YouTube username preview")
	demo.services.chat.overlay.append_message("Offline sample", "Background opacity changes; text stays visible")
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.artifacts/demo-on.png")
	demo.services.chat.open_settings()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.artifacts/chat-settings.png")
	demo.queue_free()
	await process_frame
	quit()

