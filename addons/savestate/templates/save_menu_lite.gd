extends CanvasLayer
## Quick save/load controls for sessions or legacy slot_0 saves.

@export var menu_theme: Theme

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if menu_theme != null: $Center/Panel.theme = menu_theme
	$Center/Panel/VBox/SaveBtn.grab_focus()
	$Center/Panel/VBox/Title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$Center/Panel.custom_minimum_size.x = 240

@export var persist_includes_saveables: bool = true


func _on_quick_save_pressed() -> void:
	var error: Error = SaveManager.persist_including_saveables() if persist_includes_saveables else SaveManager.persist()
	$Center/Panel/VBox/Title.text = "Saved" if error == OK else "Save failed: " + error_string(error)


func _on_quick_load_pressed() -> void:
	if SaveManager.get_active_context()["enabled"] or DirAccess.dir_exists_absolute(SaveManager.save_root.path_join(".profiles")):
		var result: SaveStateResult = SaveManager.load_game()
		$Center/Panel/VBox/Title.text = "Loaded" if result.ok else result.message
	else:
		SaveManager.load_from_slot_and_apply_saveables(&"slot_0")
		var result: SaveStateLoadResult = SaveManager.get_last_load_result()
		$Center/Panel/VBox/Title.text = "Loaded" if result.ok else result.message
