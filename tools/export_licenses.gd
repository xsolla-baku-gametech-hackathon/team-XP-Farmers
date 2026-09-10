extends SceneTree
## Include the engine and bundled dependency notices alongside exported binaries.


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Supply the output notice filename after --")
		quit(1)
		return
	var notice := "GODOT ENGINE\n\n" + Engine.get_license_text()
	notice += "\n\nTHIRD-PARTY COPYRIGHT NOTICES\n\n"
	for component in Engine.get_copyright_info():
		notice += JSON.stringify(component, "  ") + "\n\n"
	notice += "\nTHIRD-PARTY LICENSE TEXTS\n\n"
	var licenses := Engine.get_license_info()
	for identifier in licenses:
		notice += String(identifier) + "\n\n" + String(licenses[identifier]) + "\n\n"
	var output := FileAccess.open(arguments[0], FileAccess.WRITE)
	if output == null:
		push_error("Could not write engine notices")
		quit(1)
		return
	output.store_string(notice)
	output.close()
	print("Engine notices exported")
	quit()
