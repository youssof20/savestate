@tool
extends VBoxContainer
## Compact dock entry point. Inspecting a save opens a workspace sized for nested data.
var get_manager: Callable
var profiles: OptionButton
var slots: ItemList
var status: Label
var filter: LineEdit
var show_deleted: CheckBox
var workbench: Window
var debugger: Object
var setup: Window
var _fingerprint: String = ""
var _selected_profile: String = "default"
var _selected_slot: String = ""
var _entries: Array = []

func _ready() -> void:
	name = "Playthroughs"
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Profile"
	title.add_theme_font_size_override("font_size", 12)
	add_child(title)
	var row := HBoxContainer.new()
	add_child(row)
	profiles = OptionButton.new()
	profiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profiles.item_selected.connect(func(index):
		_selected_profile = str(profiles.get_item_metadata(index))
		_selected_slot = ""
		refresh_slots()
	)
	row.add_child(profiles)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.tooltip_text = "Saves also refresh automatically while this panel is visible."
	refresh.pressed.connect(refresh_profiles)
	row.add_child(refresh)
	filter = LineEdit.new()
	filter.placeholder_text = "Filter saves…"
	filter.clear_button_enabled = true
	filter.text_changed.connect(func(_text): _fill())
	add_child(filter)
	show_deleted = CheckBox.new()
	show_deleted.text = "Show deleted saves"
	show_deleted.toggled.connect(func(_on): refresh_slots())
	add_child(show_deleted)
	slots = ItemList.new()
	slots.max_text_lines = 2
	slots.add_theme_constant_override("v_separation", 8)
	slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots.custom_minimum_size = Vector2(180, 160)
	slots.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	slots.item_selected.connect(func(index): _selected_slot = str(slots.get_item_metadata(index).id))
	slots.item_activated.connect(func(_index): inspect_selected())
	add_child(slots)
	var inspect := Button.new()
	inspect.text = "Inspect save"
	inspect.pressed.connect(inspect_selected)
	add_child(inspect)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 12)
	add_child(status)
	var setup_button := Button.new()
	setup_button.text = "Setup and validation…"
	setup_button.pressed.connect(func():
		if setup == null:
			setup = preload("res://addons/savestate/editor/setup_workbench.gd").new()
			setup.get_manager = get_manager
			add_child(setup)
		setup.popup_centered_clamped(Vector2i(740, 580), 0.85)
	)
	add_child(setup_button)
	var folder := Button.new()
	folder.text = "Open save folder"
	folder.flat = true
	folder.pressed.connect(func():
		var manager: SaveManagerBase = get_manager.call()
		if manager != null: OS.shell_open(ProjectSettings.globalize_path(manager.save_root))
	)
	add_child(folder)
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	call_deferred("refresh_profiles")

func refresh_profiles() -> void:
	profiles.clear()
	var manager: SaveManagerBase = get_manager.call()
	if manager == null:
		status.text = "Enable SaveState in Project Settings → Plugins."
		return
	var listing := SaveStateCatalogue.scan(manager, manager.save_root.path_join(".profiles"), true)
	if not listing.ok:
		status.text = listing.message
		return
	for entry in listing.data.entries:
		if entry.get("deleted", false): continue
		profiles.add_item(entry.display_name)
		var index := profiles.item_count - 1
		profiles.set_item_metadata(index, entry.id)
		if entry.id == _selected_profile: profiles.select(index)
	if profiles.selected >= 0: _selected_profile = str(profiles.get_item_metadata(profiles.selected))
	refresh_slots()

func refresh_slots() -> void:
	_entries.clear()
	if profiles.selected < 0:
		slots.clear()
		status.text = "No saved games yet. Run the game and save once."
		return
	var manager: SaveManagerBase = get_manager.call()
	if manager == null: return
	var listing := SaveStateCatalogue.scan(manager, SaveStateCatalogue.profile_root(manager.save_root, _selected_profile))
	if not listing.ok:
		status.text = listing.message
		return
	_entries = listing.data.entries.filter(func(entry): return show_deleted.button_pressed or not entry.get("deleted", false))
	_fill()
	status.tooltip_text = ProjectSettings.globalize_path(manager.save_root)

func _fill() -> void:
	slots.clear()
	for entry in _entries:
		if filter.text != "" and not str(entry.display_name).to_lower().contains(filter.text.to_lower()): continue
		var state := "Saved" if entry.status == "ok" else str(entry.status).replace("_", " ").capitalize()
		if entry.has("recovery_generation_id"): state = "Needs recovery"
		var when := SaveStateUnixDisplay.format_modified_time(int(entry.get("saved_unix", 0))).substr(5, 11)
		var index := slots.add_item(str(entry.display_name) + (" · " + state if entry.status != "ok" else ""))
		slots.set_item_metadata(index, entry)
		slots.set_item_tooltip(index, "%s\n%s · %s\nDouble-click to inspect data and history." % [entry.display_name, state, when])
		if entry.id == _selected_slot: slots.select(index)
	if slots.item_count > 0 and slots.get_selected_items().is_empty():
		slots.select(0)
		_selected_slot = str(slots.get_item_metadata(0).id)
	status.text = "No matching saves." if slots.item_count == 0 else "%d saves · updates automatically" % slots.item_count

func inspect_selected() -> void:
	if slots.get_selected_items().is_empty(): return
	var manager: SaveManagerBase = get_manager.call()
	if workbench == null:
		workbench = preload("res://addons/savestate/editor/save_workbench.gd").new()
		workbench.get_manager = get_manager
		workbench.debugger = debugger
		workbench.changed.connect(refresh_profiles)
		add_child(workbench)
	workbench.request_open(_selected_profile, _selected_slot)

func _poll() -> void:
	if not is_visible_in_tree(): return
	var manager: SaveManagerBase = get_manager.call()
	if manager == null: return
	var signature := _signature(manager.save_root, 0)
	if signature != _fingerprint:
		_fingerprint = signature
		refresh_profiles()

func _signature(path: String, depth: int) -> String:
	if depth > 5: return ""
	var directory := DirAccess.open(path)
	if directory == null: return ""
	directory.include_hidden = true
	var result := ""
	for file in directory.get_files():
		if file.ends_with(".ssv"): result += path + file + str(FileAccess.get_modified_time(path.path_join(file)))
	for folder in directory.get_directories(): result += _signature(path.path_join(folder), depth + 1)
	return result
