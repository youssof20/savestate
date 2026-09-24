extends Node2D

@onready var player: CharacterBody2D = $Player
var xp: int = 0
var stash: Dictionary = {"herbs": 0, "potions": 0}
var stats: Label
var status: Label
var checkpoint_name: LineEdit
var controls: Array[Button] = []
var ready_to_play := false

func _ready() -> void:
	build_ui()
	SaveManager.register_key(&"gold", TYPE_INT, 0)
	SaveManager.register_key(&"xp", TYPE_INT, 0)
	SaveManager.register_key(&"position", TYPE_VECTOR2, Vector2(650, 300))
	SaveManager.register_key(&"accent", TYPE_COLOR, Color(0.25, 0.55, 0.95))
	SaveManager.register_key(&"stash", TYPE_DICTIONARY, {"herbs": 0, "potions": 0})
	var result := SaveManager.start_session()
	ready_to_play = result.ok
	for button in controls: button.disabled = not result.ok
	if result.ok: apply_state()
	status.text = "Ready" if result.ok else result.message

func build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(320, 560)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172d35")
	style.set_content_margin_all(18)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	panel.add_child(body)
	var title := Label.new()
	title.text = "SaveState Lite"
	title.add_theme_font_size_override("font_size", 24)
	body.add_child(title)
	stats = Label.new()
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(stats)
	var actions := HFlowContainer.new()
	body.add_child(actions)
	button(actions, "+10 gold", func(): player.gold += 10)
	button(actions, "+5 XP", func(): xp += 5)
	button(actions, "+1 herb", func(): stash.herbs += 1)
	button(actions, "+1 potion", func(): stash.potions += 1)
	button(actions, "Change color", func(): player.set_accent(Color.from_hsv(fmod(player.accent.h + 0.12, 1.0), 0.72, 0.95)))
	body.add_child(HSeparator.new())
	var save_actions := HFlowContainer.new()
	body.add_child(save_actions)
	button(save_actions, "Save", func(): save_state())
	button(save_actions, "Load", func(): confirm_load())
	checkpoint_name = LineEdit.new()
	checkpoint_name.text = "checkpoint"
	checkpoint_name.placeholder_text = "Checkpoint name"
	body.add_child(checkpoint_name)
	button(body, "Save checkpoint", func(): checkpoint_action(false))
	button(body, "Load checkpoint", func(): checkpoint_action(true))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	var hint := Label.new()
	hint.text = "Arrow keys to move. Save, then restart to resume."
	hint.position = Vector2(380, 24)
	canvas.add_child(hint)

func button(parent: Node, text: String, action: Callable) -> void:
	var item := Button.new()
	item.text = text
	item.pressed.connect(action)
	parent.add_child(item)
	controls.append(item)

func _process(_delta: float) -> void:
	stats.text = "Gold: %d   XP: %d\nHerbs: %d   Potions: %d\nPosition: %.0f, %.0f" % [player.gold, xp, stash.herbs, stash.potions, player.position.x, player.position.y]

func apply_state() -> void:
	player.gold = SaveManager.get_value(&"gold", 0)
	xp = SaveManager.get_value(&"xp", 0)
	stash = SaveManager.get_value(&"stash", {"herbs": 0, "potions": 0}).duplicate(true)
	player.position = SaveManager.get_value(&"position", Vector2(650, 300))
	player.set_accent(SaveManager.get_value(&"accent", Color(0.25, 0.55, 0.95)))

func save_state(slot: StringName = &"") -> void:
	if not ready_to_play: return
	SaveManager.set_value(&"gold", player.gold)
	SaveManager.set_value(&"xp", xp)
	SaveManager.set_value(&"stash", stash.duplicate(true))
	SaveManager.set_value(&"position", player.position)
	SaveManager.set_value(&"accent", player.accent)
	var result := await SaveManager.save_game(slot)
	status.text = "Saved" if result.ok else result.message

func confirm_load(slot: StringName = &"") -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Load saved game?"
	dialog.dialog_text = "Replace the current state with this save?"
	add_child(dialog)
	dialog.confirmed.connect(func(): load_state(slot); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func load_state(slot: StringName = &"") -> void:
	var result := SaveManager.load_game(slot, false, true)
	if result.ok: apply_state()
	status.text = "Loaded" if result.ok else result.message

func checkpoint_action(loading: bool) -> void:
	var name := checkpoint_name.text.strip_edges()
	if name.is_empty():
		status.text = "Enter a checkpoint name."
		checkpoint_name.grab_focus()
		return
	if loading: confirm_load(StringName(name))
	else: save_state(StringName(name))
