@tool
extends EditorPlugin

var failed := false

func _enter_tree() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		printerr("FAIL: " + label)

func run() -> void:
	for frame in 8: await get_tree().process_frame
	check(EditorInterface.is_plugin_enabled("savestate"), "Lite enabled")
	check(get_tree().get_nodes_in_group("savestate_save_browser").size() == 1, "one save dock")
	check(ProjectSettings.has_setting("autoload/SaveManager"), "autoload installed")
	var manager := SaveManagerBase.new()
	manager.save_root = "res://editor-scratch"
	add_child(manager)
	check(manager.start_session().ok, "editor fixture session")
	manager.set_value(&"coins", 20)
	check((await manager.save_game()).ok, "editor fixture save")
	var context := manager.get_active_context()
	var window = load("res://addons/savestate/editor/save_workbench.gd").new()
	window.get_manager = func(): return manager
	add_child(window)
	window.open_save(str(context.profile_id), str(context.slot_id))
	check(window.source.ok, "inspector reads saved data")
	var before := FileAccess.get_sha256(window.source.path)
	check(window.store.write(window.source, {}).status == &"unsupported_capability", "editor writes refused")
	check(window.store.preview(window.source).status == &"unsupported_capability", "Pro preview refused")
	check(FileAccess.get_sha256(window.source.path) == before, "inspection preserves source")
	for index in window.tabs.get_tab_count():
		var title: String = window.tabs.get_tab_title(index)
		check(window.tabs.is_tab_hidden(index) == (title in ["Changes", "Upgrade", "Live"]), "tab visibility: " + title)
	check(not window.apply_button.visible, "save edits hidden")
	check(window.history_list.item_count > 0, "history shown")
	window.queue_free()
	manager.queue_free()
	await get_tree().process_frame
	EditorInterface.set_plugin_enabled("savestate", false)
	for frame in 8: await get_tree().process_frame
	check(not ProjectSettings.has_setting("autoload/SaveManager"), "disable removes autoload")
	EditorInterface.set_plugin_enabled("savestate", true)
	for frame in 8: await get_tree().process_frame
	check(get_tree().get_nodes_in_group("savestate_save_browser").size() == 1, "reenable restores one dock")
	print("Lite editor checks: " + ("FAIL" if failed else "PASS"))
	get_tree().quit(1 if failed else 0)
