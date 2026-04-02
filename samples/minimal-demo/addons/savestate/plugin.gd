@tool
extends EditorPlugin

const AUTOLOAD_NAME := "SaveManager"
const AUTOLOAD_PATH := "res://addons/savestate/save_manager.gd"
const SAVE_BROWSER_DOCK := "res://addons/savestate/editor/save_browser_dock.gd"

var _dock: Control


func get_plugin_name() -> String:
	return "SaveState (Lite)"


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	_register_default_project_settings()
	if ResourceLoader.exists(SAVE_BROWSER_DOCK):
		_dock = load(SAVE_BROWSER_DOCK).new() as Control
		if _dock != null:
			_dock.name = "SaveBrowserDock"
			add_control_to_dock(DOCK_SLOT_LEFT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	# Do not remove if SaveState Pro replaced the autoload with pro_manager.gd
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		return
	var raw_path := str(ProjectSettings.get_setting("autoload/" + AUTOLOAD_NAME))
	var path := raw_path.strip_edges().trim_prefix("*")
	if path == AUTOLOAD_PATH:
		remove_autoload_singleton(AUTOLOAD_NAME)


func _register_default_project_settings() -> void:
	const KEY_VERSION := "savestate/current_version"
	if not ProjectSettings.has_setting(KEY_VERSION):
		ProjectSettings.set_setting(KEY_VERSION, 1)
		var prop_info := {
			"name": KEY_VERSION,
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "1,2147483647,1",
		}
		ProjectSettings.add_property_info(prop_info)
