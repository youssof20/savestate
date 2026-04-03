extends CanvasLayer
## Lite v1.2 drop-in template: wire the buttons (or duplicate this scene). Uses reserved [code]slot_0[/code] KV + optional saveables.

@export var persist_includes_saveables: bool = true


func _on_quick_save_pressed() -> void:
	if persist_includes_saveables:
		SaveManager.persist_including_saveables()
	else:
		SaveManager.persist()


func _on_quick_load_pressed() -> void:
	SaveManager.load_from_slot_and_apply_saveables(&"slot_0")
