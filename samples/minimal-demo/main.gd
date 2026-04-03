extends Node2D
## Starter: SaveManager KV with several types (int, float, Color, Dictionary) + [method SaveManager.register_key] for validation.
## Save / Load mirror what you would do in a real game; open Save Browser → Data to inspect or edit keys live.

@onready var player: CharacterBody2D = $Player
@onready var stats_label: Label = $CanvasLayer/UI/VBox/StatsLabel
@onready var slot_name_edit: LineEdit = $CanvasLayer/UI/VBox/SlotRow/SlotNameEdit

var _xp: int = 0
## Simple loot table demo — one Dictionary key in the save file (see Save Browser JSON / Data tab).
var _stash: Dictionary = {"herbs": 0, "potions": 0}


func _ready() -> void:
	_register_demo_keys()
	SaveManager.migration_required.connect(_on_migration_required)
	_load_all_from_save()
	slot_name_edit.placeholder_text = _suggest_next_free_slot_base()
	if slot_name_edit.text.strip_edges().is_empty():
		slot_name_edit.text = slot_name_edit.placeholder_text


func _register_demo_keys() -> void:
	SaveManager.register_key(&"gold", TYPE_INT, 0)
	SaveManager.register_key(&"player_x", TYPE_FLOAT, 400.0)
	SaveManager.register_key(&"player_y", TYPE_FLOAT, 300.0)
	SaveManager.register_key(&"xp", TYPE_INT, 0)
	SaveManager.register_key(&"accent", TYPE_COLOR, Color(0.25, 0.55, 0.95))
	SaveManager.register_key(&"stash", TYPE_DICTIONARY, {"herbs": 0, "potions": 0})


func _load_all_from_save() -> void:
	player.gold = int(SaveManager.get_value(&"gold", 0))
	var px := float(SaveManager.get_value(&"player_x", 400.0))
	var py := float(SaveManager.get_value(&"player_y", 300.0))
	player.global_position = Vector2(px, py)
	_xp = int(SaveManager.get_value(&"xp", 0))
	var col: Variant = SaveManager.get_value(&"accent", Color(0.25, 0.55, 0.95))
	if col is Color:
		player.set_accent(col as Color)
	else:
		player.set_accent(Color(0.25, 0.55, 0.95))
	var bag: Variant = SaveManager.get_value(&"stash", {"herbs": 0, "potions": 0})
	if bag is Dictionary:
		_stash = (bag as Dictionary).duplicate(true)
	else:
		_stash = {"herbs": 0, "potions": 0}


func _process(_delta: float) -> void:
	var hx := player.global_position.x
	var hy := player.global_position.y
	stats_label.text = (
		"Gold: %d  |  XP: %d\n"
		+ "Position: (%.0f, %.0f)  — arrow keys to move\n"
		+ "Stash: herbs=%d  potions=%d\n"
		+ "Save → slot_0; named slot = extra file (slot_0 unchanged)\n"
		+ "Pro: Save also writes slot_0.jpg (viewport grab)"
	) % [
		player.gold,
		_xp,
		hx,
		hy,
		int(_stash.get("herbs", 0)),
		int(_stash.get("potions", 0)),
	]


func _on_migration_required(old_v: int, new_v: int) -> void:
	print("SaveState: migration hook — file schema ", old_v, " → project ", new_v, " (add your fix-up here)")


func _on_add_gold_pressed() -> void:
	player.gold += 10


func _on_add_xp_pressed() -> void:
	_xp += 5


func _on_add_herb_pressed() -> void:
	_stash["herbs"] = int(_stash.get("herbs", 0)) + 1


func _on_add_potion_pressed() -> void:
	_stash["potions"] = int(_stash.get("potions", 0)) + 1


func _on_cycle_color_pressed() -> void:
	var h: float = player.accent.h
	h = fmod(h + 0.12, 1.0)
	var c: Color = Color.from_hsv(h, 0.72, 0.95, 1.0)
	player.set_accent(c)


func _write_kv_to_savemanager() -> void:
	SaveManager.set_value(&"gold", player.gold)
	SaveManager.set_value(&"player_x", player.global_position.x)
	SaveManager.set_value(&"player_y", player.global_position.y)
	SaveManager.set_value(&"xp", _xp)
	SaveManager.set_value(&"accent", player.accent)
	SaveManager.set_value(&"stash", _stash.duplicate(true))


func _on_save_pressed() -> void:
	_write_kv_to_savemanager()
	SaveManager.persist()


func _named_slot_id() -> StringName:
	var s := slot_name_edit.text.strip_edges()
	if s.is_empty():
		s = slot_name_edit.placeholder_text.strip_edges()
	if s.is_empty():
		return &""
	# File base only (slot_2 → slot_2.bin). Strip accidental extension.
	s = s.get_file().get_basename()
	return StringName(s)


## [method SaveManager.export_current_to_slot] writes [code]slot_N.bin[/code] (Pro adds [code]slot_N.jpg[/code]) without touching [code]slot_0[/code].
func _on_save_named_slot_pressed() -> void:
	var sid := _named_slot_id()
	if str(sid).is_empty():
		push_warning("Enter a slot file base (e.g. slot_2 or checkpoint_boss).")
		return
	_write_kv_to_savemanager()
	var err: Error = SaveManager.export_current_to_slot(sid) as Error
	if err != OK:
		push_warning("export_current_to_slot(%s) failed: %s" % [str(sid), error_string(err)])


func _on_next_free_slot_pressed() -> void:
	var s := _suggest_next_free_slot_base()
	slot_name_edit.text = s
	slot_name_edit.placeholder_text = s


func _suggest_next_free_slot_base() -> String:
	var root := str(SaveManager.save_root).strip_edges()
	if root.is_empty():
		root = "user://savestate"
	var used: Dictionary = {}
	var dir := DirAccess.open(root)
	if dir == null:
		return "slot_2"
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			var bn := fn.get_basename()
			if bn.begins_with("slot_") or fn.ends_with(".bin") or fn.ends_with(".json"):
				used[bn] = true
		fn = dir.get_next()
	dir.list_dir_end()
	for i in range(1, 99):
		var cand := "slot_%d" % i
		if not used.has(cand):
			return cand
	return "slot_99"


func _on_load_pressed() -> void:
	SaveManager.clear_kv_cache()
	_load_all_from_save()


func _on_load_named_slot_pressed() -> void:
	var sid := _named_slot_id()
	if str(sid).is_empty():
		push_warning("Enter a slot file base to load.")
		return
	var err: Error = SaveManager.import_slot_into_runtime(sid) as Error
	if err != OK:
		push_warning("import_slot_into_runtime(%s) failed: %s" % [str(sid), error_string(err)])
		return
	_load_all_from_save()
