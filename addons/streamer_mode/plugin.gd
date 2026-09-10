@tool
extends EditorPlugin
## Editor-time convenience for the Streamer Mode privacy module.
##
## Adds two entries under Project > Tools that tag the selected Control node(s)
## into the "privacy_sensitive" group (persisted in the scene). At runtime a
## PrivacyEngine with `auto_register_from_group` on masks every node in that
## group - no register_node() calls needed for the common case.
##
## Enabling this plugin is optional. The runtime classes (PrivacyEngine,
## PrivacyBlurMask, PrivacyCopyField, PrivacyControlPanel) register their
## `class_name` globals whether or not the plugin is enabled; this script only
## provides the editor buttons.

const GROUP := "privacy_sensitive"
const TAG_ITEM := "Privacy: tag selected node(s) as Private"
const UNTAG_ITEM := "Privacy: untag selected node(s)"


func _enter_tree() -> void:
	add_tool_menu_item(TAG_ITEM, _tag_selected)
	add_tool_menu_item(UNTAG_ITEM, _untag_selected)


func _exit_tree() -> void:
	remove_tool_menu_item(TAG_ITEM)
	remove_tool_menu_item(UNTAG_ITEM)


func _tag_selected() -> void:
	_apply(true)


func _untag_selected() -> void:
	_apply(false)


func _apply(add: bool) -> void:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	var count := 0
	for node in nodes:
		if not (node is Control):
			continue
		if add:
			node.add_to_group(GROUP, true)  # persistent -> saved in the .tscn
		else:
			node.remove_from_group(GROUP)
		count += 1
	var verb := "Tagged" if add else "Untagged"
	if count == 0:
		push_warning("Streamer Mode: select one or more Control nodes first.")
		return
	print("Streamer Mode: %s %d node(s) in group \"%s\". Save the scene to keep it." % [verb, count, GROUP])
	if EditorInterface.has_method("mark_scene_as_unsaved"):
		EditorInterface.mark_scene_as_unsaved()
