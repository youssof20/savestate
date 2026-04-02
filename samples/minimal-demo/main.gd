extends Node2D
## Starter flow: three API calls for save, three for load (see _on_save_pressed / _on_load_pressed).

@onready var player: CharacterBody2D = $Player
@onready var gold_label: Label = $CanvasLayer/UI/VBox/GoldLabel


func _ready() -> void:
	SaveManager.migration_required.connect(_on_migration_required)
	# Load persisted gold from slot_0 KV (first run uses default 0).
	player.gold = int(SaveManager.get_value(&"gold", 0))


func _process(_delta: float) -> void:
	gold_label.text = "Gold: %d  (arrow keys to move)" % player.gold


func _on_migration_required(old_v: int, new_v: int) -> void:
	print("SaveState: migration hook — file schema ", old_v, " → project ", new_v, " (add your fix-up here)")


func _on_add_gold_pressed() -> void:
	player.gold += 10


func _on_save_pressed() -> void:
	SaveManager.set_value(&"gold", player.gold)
	SaveManager.persist()


func _on_load_pressed() -> void:
	SaveManager.clear_kv_cache()
	player.gold = int(SaveManager.get_value(&"gold", 0))
