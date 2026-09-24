@tool
extends Window
signal changed
var get_manager: Callable
var debugger: Object
var store: SaveStateEditorStore
var source: SaveStateResult
var document := SaveStateEditSession.new()
var profile: String = ""
var slot: String = ""
var heading: Label
var feedback: Label
var search: LineEdit
var data_tree: Tree
var history_list: ItemList
var diff_text: TextEdit
var details: TextEdit
var migration_text: TextEdit
var tabs: TabContainer
var apply_button: Button
var undo_button: Button
var redo_button: Button
var migration_candidate: SaveStateResult
var batch_previews: Array = []
var confirm: ConfirmationDialog
var pending_navigation: Callable
var row_count: int = 0
var _pro: bool = false
var _expanded: Dictionary = {}
var _selected_path: Array = []
var _loading: bool = false
var _live_pending: bool = false
var thumbnail: TextureRect
var thumbnail_note: Label
var runtime_sessions: OptionButton
var _buttons: Array[Button] = []

func _ready() -> void:
	hide()
	title = "SaveState · Saved game"
	size = Vector2i(1000, 700)
	min_size = Vector2i(560, 420)
	unresizable = false
	transient = true
	close_requested.connect(func(): navigate(hide))
	var background := PanelContainer.new()
	background.theme = EditorInterface.get_editor_theme()
	var panel := StyleBoxFlat.new()
	panel.bg_color = EditorInterface.get_editor_settings().get_setting("interface/theme/base_color")
	panel.set_corner_radius_all(5)
	background.add_theme_stylebox_override("panel", panel)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 16)
	background.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 22)
	body.add_child(heading)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(feedback)
	var bar := HFlowContainer.new()
	body.add_child(bar)
	apply_button = button(bar, "Save changes", func(): commit("edit"))
	button(bar, "Save as copy…", func(): name_dialog("Save as copy", "branch"))
	button(bar, "Rename…", func(): name_dialog("Rename saved game", "rename"))
	button(bar, "Reload", func(): navigate(func(): open_save(profile, slot)))

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	var data := VBoxContainer.new()
	data.name = "Data"
	tabs.add_child(data)
	var edit_bar := HFlowContainer.new()
	data.add_child(edit_bar)
	undo_button = button(edit_bar, "Undo", func(): document.undo(); refill())
	redo_button = button(edit_bar, "Redo", func(): document.redo(); refill())
	button(edit_bar, "Edit value…", edit_selected)
	button(edit_bar, "Insert…", insert_selected)
	button(edit_bar, "Remove", remove_selected)
	button(edit_bar, "Discard changes", func(): confirmation("Discard changes?", "Return this document to the version you opened?", func(): document.open(document.original); refill()))
	search = LineEdit.new()
	search.placeholder_text = "Find a field or path…"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text): refill())
	data.add_child(search)
	data_tree = Tree.new()
	data_tree.columns = 3
	data_tree.column_titles_visible = true
	for i in 3: data_tree.set_column_title(i, ["Field", "Type", "Value"][i])
	data_tree.set_column_expand_ratio(0, 3)
	data_tree.set_column_expand_ratio(1, 1)
	data_tree.set_column_expand_ratio(2, 3)
	data_tree.hide_root = false
	data_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	data_tree.item_activated.connect(edit_selected)
	data.add_child(data_tree)
	var changes := VBoxContainer.new()
	changes.name = "Changes"
	tabs.add_child(changes)
	diff_text = text_view(changes)
	var history := VBoxContainer.new()
	history.name = "History"
	tabs.add_child(history)
	history_list = ItemList.new()
	history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history.add_child(history_list)
	var hbar := HFlowContainer.new()
	history.add_child(hbar)
	button(hbar, "Inspect generation", inspect_history)
	button(hbar, "Compare with open data", compare_history)
	button(hbar, "Restore generation…", restore_history)
	var migration := VBoxContainer.new()
	migration.name = "Upgrade"
	tabs.add_child(migration)
	var mbar := HFlowContainer.new()
	migration.add_child(mbar)
	button(mbar, "Preview upgrade", preview_upgrade)
	button(mbar, "Write preview as new generation…", func():
		if migration_candidate != null and migration_candidate.ok:
			confirmation("Apply schema upgrade?", "Write the preview as a new generation? The source generation is retained.", func(): commit("migrate"))
		else: message("Run a successful preview first.")
	)
	button(mbar, "Preview profile", preview_profile)
	button(mbar, "Write eligible previews…", commit_batch)
	migration_text = text_view(migration)
	migration_text.text = "Preview schema changes without changing saved data. Configure savestate/schema_setup_script so game and editor register the same pure migrations."
	var diagnostic := VBoxContainer.new()
	diagnostic.name = "Details"
	tabs.add_child(diagnostic)
	thumbnail = TextureRect.new()
	thumbnail.custom_minimum_size = Vector2(240, 135)
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	diagnostic.add_child(thumbnail)
	thumbnail_note = Label.new()
	thumbnail_note.text = "No preview image was saved."
	diagnostic.add_child(thumbnail_note)
	details = text_view(diagnostic)
	button(diagnostic, "Copy safe diagnostics", func(): DisplayServer.clipboard_set(safe_diagnostics()))
	var tools := HFlowContainer.new()
	diagnostic.add_child(tools)
	button(tools, "Export debug JSON…", export_json)
	button(tools, "Delete saved game…", func(): confirmation("Delete saved game?", "Hide this saved game from the catalogue? Retained generations remain on disk.", func(): commit("delete")))
	var live_panel := VBoxContainer.new()
	live_panel.name = "Live"
	tabs.add_child(live_panel)
	tabs.move_child(live_panel, 4)
	var explanation := Label.new()
	explanation.text = "Inspect and edit a connected game's memory. Saving to disk is a separate acknowledged action."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	live_panel.add_child(explanation)
	var live := HFlowContainer.new()
	live_panel.add_child(live)
	runtime_sessions = OptionButton.new()
	runtime_sessions.add_item("One connected game", -1)
	live.add_child(runtime_sessions)
	button(live, "Sessions", refresh_sessions)
	button(live, "Apply to running game", apply_live)
	button(live, "Compare running game", compare_live)
	button(live, "Save running game", func():
		if debugger != null and debugger.request_save(profile, slot, runtime_sessions.get_selected_id(), ProjectSettings.globalize_path(store.manager.save_root)):
			_live_pending = true
			message("Waiting for disk-save acknowledgement…")
		else: message("Choose a connected game and wait for its current request.")
	)
	if debugger != null:
		debugger.runtime_result.connect(func(error, revision, destination):
			_live_pending = false
			if not visible: return
			if error != OK: message("Runtime request failed (%s). The active save or revision may have changed. World fields require a full load." % error_string(error))
			else: message("Saved to disk · runtime revision %d" % revision if destination == "disk" else "Applied to game memory · revision %d · not yet saved to disk" % revision)
		)
		debugger.snapshot_received.connect(func(state):
			_live_pending = false
			if not visible: return
			diff_text.text = "Open saved document → running game\n\n" + describe_diff(SaveStateEditSession.diff(document.original, state.data))
			tabs.current_tab = 1
			message("Compared with runtime revision %d. No data changed." % state.revision)
		)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(footer)
	button(footer, "Close", func(): navigate(hide))
	confirm = ConfirmationDialog.new()
	add_child(confirm)

func button(parent: Node, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.pressed.connect(action)
	parent.add_child(item)
	_buttons.append(item)
	return item

func text_view(parent: Node) -> TextEdit:
	var text := TextEdit.new()
	text.editable = false
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(text)
	return text

func request_open(profile_id: String, slot_id: String) -> void:
	navigate(func(): open_save(profile_id, slot_id))
	if not visible: popup_centered_clamped(Vector2i(1000, 700), 0.88)

func open_save(profile_id: String, slot_id: String, generation: String = "") -> void:
	store = SaveStateEditorStore.new(get_manager.call())
	_pro = store.manager.supports_profiles()
	apply_edition()
	profile = profile_id
	slot = slot_id
	source = store.read(profile, slot, generation)
	migration_candidate = null
	document.open(source.data if source.ok else {})
	if source.ok:
		heading.text = source.metadata.catalogue.display_name
		title = "SaveState · " + heading.text
		message("Saved on disk · generation %d · schema %d" % [source.sequence, source.schema_version])
	else:
		heading.text = "Saved game unavailable"
		message(source.message + " Check History for a retained version.")
	thumbnail.texture = null
	thumbnail_note.visible = true
	if source.ok and not source.thumbnail.is_empty():
		var picture := Image.new()
		var error := picture.load_jpg_from_buffer(source.thumbnail) if source.thumbnail[0] == 255 else picture.load_png_from_buffer(source.thumbnail)
		if error == OK:
			thumbnail.texture = ImageTexture.create_from_image(picture)
			thumbnail_note.visible = false
	refresh_history()
	refill()
	details.text = safe_diagnostics()

func apply_edition() -> void:
	var inspection_actions := ["Reload", "Inspect generation", "Copy safe diagnostics", "Export debug JSON…", "Close"]
	for item in _buttons:
		item.visible = _pro or item.text in inspection_actions
	for index in tabs.get_tab_count():
		tabs.set_tab_hidden(index, not _pro and tabs.get_tab_title(index) in ["Changes", "Upgrade", "Live"])
	if tabs.is_tab_hidden(tabs.current_tab): tabs.current_tab = 0


func message(text: String) -> void:
	feedback.text = text

func safe_diagnostics() -> String:
	if source == null: return "No save selected."
	return "Edition: %s\nEngine: %s\nProfile: %s\nSlot: %s\nGeneration: %s\nSchema: %d\nStatus: %s\nPending edits: %s\nStage timings (microseconds): %s\n\nNo keys or gameplay values are included." % ["Pro" if _pro else "Lite", Engine.get_version_info().string, profile, slot, source.generation_id, source.schema_version, source.status, document.dirty(), source.timings_usec]

func editable() -> bool:
	if not _pro: message("Data inspection is available in Lite. Typed changes require Pro."); return false
	if source == null or not source.ok: message("Select a readable generation first."); return false
	return true

func refill() -> void:
	remember_tree(data_tree.get_root())
	data_tree.clear()
	row_count = 0
	var root := data_tree.create_item()
	root.set_text(0, "Saved data")
	root.set_metadata(0, {"path": [], "value": document.current})
	add_rows(document.current, [], root)
	undo_button.disabled = document.undo_stack.is_empty()
	redo_button.disabled = document.redo_stack.is_empty()
	apply_button.disabled = not _pro or not document.dirty() or source == null or not source.ok or source.generation_id != source.metadata.get("editor_head", "")
	diff_text.text = describe_diff(SaveStateEditSession.diff(document.original, document.current))
	if document.dirty(): message("Unsaved edits · review Changes, then Save changes or Save as copy.")
	elif source != null and source.ok: message("Saved on disk · generation %d · schema %d" % [source.sequence, source.schema_version])
	if row_count >= 2500: message("Showing the first 2,500 matching fields. Refine the search to find others.")

func add_rows(value: Variant, path: Array, parent: TreeItem) -> void:
	if path.size() > 32: return
	var keys: Array = value.keys() if value is Dictionary else range(value.size())
	for key in keys:
		if row_count >= 2500: return
		var next := path + [{"key": key} if value is Dictionary else {"index": key}]
		var child_value: Variant = value[key]
		var container := child_value is Array or child_value is Dictionary
		var matches := search.text == "" or SaveStateEditSession.path_label(next).to_lower().contains(search.text.to_lower())
		var item: TreeItem = parent
		if matches or container:
			item = data_tree.create_item(parent)
			row_count += 1
			item.set_text(0, str(key))
			item.set_text(1, type_string(typeof(child_value)))
			item.set_text(2, SaveStateEditSession.summary(child_value))
			item.set_tooltip_text(0, SaveStateEditSession.path_label(next))
			item.set_metadata(0, {"path": next, "value": child_value})
			item.collapsed = search.text == "" and bool(_expanded.get(var_to_str(next), path.size() > 0))
			if next == _selected_path: item.select(0)
		if container: add_rows(child_value, next, item)

func selected() -> Dictionary:
	var item := data_tree.get_selected()
	return {} if item == null else item.get_metadata(0)

func edit_selected() -> void:
	if not editable(): return
	var target := selected()
	if target.is_empty() or target.path.is_empty(): return
	if target.value is Dictionary or target.value is Array:
		message("Expand this container to edit a field, or use Insert / Remove."); return
	if typeof(target.value) >= TYPE_PACKED_BYTE_ARRAY:
		message("Packed arrays are preserved exactly. Expand ordinary arrays for element editing; packed-array editing is not supported here."); return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Edit " + SaveStateEditSession.path_label(target.path)
	dialog.min_size = Vector2i(440, 160)
	var field := LineEdit.new()
	field.text = str(target.value)
	field.placeholder_text = "Value (vectors/colors: comma-separated components)"
	dialog.add_child(field)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var parsed := SaveStateEditSession.parse(field.text, target.value)
		if not parsed.ok: message("Invalid %s value. No changes applied." % type_string(typeof(target.value)))
		else: apply_edit({"path": target.path, "before": target.value, "value": parsed.value})
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
	field.grab_focus()
	field.select_all()

func apply_edit(operation: Dictionary) -> void:
	if not editable(): return
	var error := document.change(operation)
	if error != OK: message("This edit is not valid for the selected field (%s)." % error_string(error)); return
	refill()

func insert_selected() -> void:
	if not editable(): return
	var target := selected()
	if target.is_empty() or not (target.value is Dictionary or target.value is Array): message("Select a dictionary or array to insert into."); return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Insert field" if target.value is Dictionary else "Append array item"
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 380
	dialog.add_child(form)
	var key := LineEdit.new()
	key.placeholder_text = "Dictionary key"
	key.visible = target.value is Dictionary
	form.add_child(key)
	var key_type := OptionButton.new()
	key_type.add_item("String key")
	key_type.add_item("Integer key")
	key_type.visible = key.visible
	form.add_child(key_type)
	var type := OptionButton.new()
	for kind in ["String", "Integer", "Float", "Boolean", "Dictionary", "Array", "Vector2", "Vector3", "Color"]: type.add_item(kind)
	form.add_child(type)
	var value := LineEdit.new()
	value.placeholder_text = "Value (containers start empty)"
	form.add_child(value)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var defaults: Array = ["", 0, 0.0, false, {}, [], Vector2.ZERO, Vector3.ZERO, Color.WHITE]
		var initial: Variant = defaults[type.selected]
		var parsed := {"ok": true, "value": initial} if initial is Dictionary or initial is Array else SaveStateEditSession.parse(value.text, initial)
		var key_value: Variant = key.text
		if target.value is Dictionary and key_type.selected == 1:
			var parsed_key := SaveStateEditDocument.parse_text(key.text, 0)
			if not parsed_key.ok: message("Enter a valid integer key."); dialog.queue_free(); return
			key_value = parsed_key.value
		if parsed.ok:
			var segment := {"key": key_value} if target.value is Dictionary else {"index": target.value.size()}
			apply_edit({"action": "insert", "path": target.path + [segment], "value": parsed.value})
		else: message("The value does not match the selected type.")
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func remove_selected() -> void:
	if not editable(): return
	var target := selected()
	if target.is_empty() or target.path.is_empty(): return
	confirmation("Remove field?", SaveStateEditSession.path_label(target.path) + " will be removed from the edited document. You can undo this before saving.", func(): apply_edit({"action": "remove", "path": target.path, "before": target.value}))

func commit(action: String, label: String = "") -> bool:
	if not editable(): return false
	var data := migration_candidate.data if action == "migrate" and migration_candidate != null else document.current
	var result := store.write(source, data, action, label)
	if not result.ok:
		message(result.message + (" Your edits are retained." if document.dirty() else ""))
		return false
	open_save(profile, str(result.slot_id))
	message("Saved as a new generation." + (" " + " ".join(result.warnings) if not result.warnings.is_empty() else ""))
	changed.emit()
	return true

func name_dialog(title_: String, action: String) -> void:
	if not editable(): return
	var dialog := ConfirmationDialog.new()
	dialog.title = title_
	var input := LineEdit.new()
	input.custom_minimum_size.x = 360
	input.text = source.metadata.catalogue.display_name + (" copy" if action == "branch" else "")
	dialog.add_child(input)
	add_child(dialog)
	dialog.confirmed.connect(func(): commit(action, input.text); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
	input.grab_focus()
	input.select_all()

func navigate(action: Callable) -> void:
	if _live_pending: message("Wait for the running game to acknowledge the request before changing documents."); return
	if not document.dirty(): action.call(); return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Unsaved changes"
	dialog.dialog_text = "Save or discard your edits before leaving this document."
	dialog.ok_button_text = "Save changes"
	dialog.add_button("Discard", true, "discard")
	add_child(dialog)
	dialog.confirmed.connect(func():
		if commit("edit"): action.call()
		dialog.queue_free()
	)
	dialog.custom_action.connect(func(_action): document.open(document.original); action.call(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func confirmation(title_: String, text: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title_
	dialog.dialog_text = text
	add_child(dialog)
	dialog.confirmed.connect(func(): action.call(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func refresh_history() -> void:
	history_list.clear()
	var listing := store.history(profile, slot)
	if not listing.ok: message(listing.message); return
	for entry in listing.data.entries:
		var index := history_list.add_item("Generation %d  ·  %s  ·  %s" % [entry.sequence, SaveStateUnixDisplay.format_modified_time(entry.created), str(entry.status).replace("_", " ")])
		history_list.set_item_metadata(index, entry)
		if source != null and entry.id == source.generation_id: history_list.select(index)
	if history_list.item_count > 0 and history_list.get_selected_items().is_empty(): history_list.select(0)

func history_id() -> String:
	return "" if history_list.get_selected_items().is_empty() else history_list.get_item_metadata(history_list.get_selected_items()[0]).id

func inspect_history() -> void:
	var id := history_id()
	if id != "": navigate(func(): open_save(profile, slot, id))

func compare_history() -> void:
	var id := history_id()
	if id == "": return
	var other := store.read(profile, slot, id)
	if not other.ok: message(other.message); return
	diff_text.text = "Selected generation → open document\n\n" + describe_diff(SaveStateEditSession.diff(other.data, document.current))
	tabs.current_tab = 1

func restore_history() -> void:
	if not _pro: message("History inspection is available in Lite; use recover_slot() for recovery. The history workflow requires Pro."); return
	var id := history_id()
	if id == "": return
	var other := store.read(profile, slot, id)
	if not other.ok: message(other.message); return
	navigate(func(): confirmation("Restore generation?", "Create a new latest generation from this retained state? Existing history remains unchanged.", func():
		var result := store.write(other, other.data, "recover")
		if result.ok: open_save(profile, slot); changed.emit(); message("Recovered as a new generation.")
		else: message(result.message)
	))

func preview_upgrade() -> void:
	if not editable(): return
	migration_candidate = store.preview(source)
	if not migration_candidate.ok: migration_text.text = migration_candidate.message; return
	migration_text.text = "Schema %d → %d · preview only\n\n%s" % [source.schema_version, store.manager.get_current_schema_version(), describe_diff(migration_candidate.metadata.changes)]

func preview_profile() -> void:
	if not _pro: message("Batch migration previews require Pro."); return
	var listing := SaveStateCatalogue.scan(store.manager, store.profile_root(profile))
	if not listing.ok: message(listing.message); return
	batch_previews.clear()
	var lines: PackedStringArray = ["Profile preview · no files written"]
	for entry in listing.data.entries:
		var candidate := store.read(profile, entry.id)
		var result := store.preview(candidate) if candidate.ok else candidate
		if result.ok and candidate.schema_version < store.manager.get_current_schema_version(): batch_previews.append({"source": candidate, "preview": result})
		lines.append("%s: %s%s" % [entry.display_name, result.status, (" · %d changes" % result.metadata.changes.size()) if result.ok else (" · " + result.message)])
	migration_text.text = "\n".join(lines)

func describe_diff(operations: Array) -> String:
	if operations.is_empty(): return "No changes."
	var lines: PackedStringArray = []
	for operation in operations.slice(0, 4096):
		lines.append("%s  %s\n  %s → %s" % [operation.get("action", "set").capitalize(), SaveStateEditSession.path_label(operation.path), SaveStateEditSession.summary(operation.get("before", "(missing)")), SaveStateEditSession.summary(operation.get("value", "(removed)"))])
	return "\n\n".join(lines)

func export_json() -> void:
	if source == null or not source.ok: return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Debug JSON"])
	dialog.title = "Export readable debug data (contains gameplay values)"
	dialog.current_file = "savestate-debug.json"
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: message("Cannot write the selected destination.")
		else:
			file.store_string(JSON.stringify({"representation": "Debug view; native values are strings. Not an importable save.", "data": document.current}, "\t"))
			file.close()
			message("Debug JSON exported. This is not an importable save.")
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.75)

func apply_live() -> void:
	if not editable() or debugger == null: message("Run one game instance from this editor to edit its memory."); return
	var operations := SaveStateEditSession.diff(document.original, document.current)
	if operations.is_empty(): message("There are no edits to apply."); return
	if not debugger.request_world_patch(profile, slot, operations, runtime_sessions.get_selected_id(), ProjectSettings.globalize_path(store.manager.save_root)): message("Choose a connected runtime session and wait for its current request.")
	else:
		_live_pending = true
		message("Waiting for runtime acknowledgement…")

func compare_live() -> void:
	if debugger == null: message("Run the game from this editor first."); return
	if not debugger.request_snapshot(profile, slot, runtime_sessions.get_selected_id(), ProjectSettings.globalize_path(store.manager.save_root)): message("No unambiguous connected runtime is available.")
	else: _live_pending = true

func refresh_sessions() -> void:
	runtime_sessions.clear()
	runtime_sessions.add_item("One connected game", -1)
	if debugger == null: return
	for id in debugger.available_sessions(): runtime_sessions.add_item("Game session %d" % id, id)

func commit_batch() -> void:
	if not editable(): return
	if batch_previews.is_empty(): message("Preview the profile first. Only older, successfully upgraded schemas are eligible."); return
	confirmation("Write schema upgrades?", "Write %d successful previews as new generations? Each save is independent. Conflicts and failures remain unchanged." % batch_previews.size(), func():
		var lines: PackedStringArray = []
		for item in batch_previews:
			var result := store.write(item.source, item.preview.data, "migrate")
			lines.append("%s: %s" % [item.source.metadata.catalogue.display_name, "Upgraded" if result.ok else result.message])
		migration_text.text = "\n".join(lines)
		batch_previews.clear()
		changed.emit()
	)

func remember_tree(item: TreeItem) -> void:
	if item == null: return
	var metadata: Variant = item.get_metadata(0)
	if metadata is Dictionary and metadata.has("path"):
		if search.text == "": _expanded[var_to_str(metadata.path)] = item.collapsed
		if item.is_selected(0): _selected_path = metadata.path
	for child in item.get_children(): remember_tree(child)
