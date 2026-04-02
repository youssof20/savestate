@tool
extends Control
## Pro Save Browser: Explorer (files + thumbnail), Data (search + edit KV), Config (runtime toggles).

const SAVE_GROUP := "savestate_saveable"
const LOG_PREFIX := "[SaveState Pro | Save Browser]"
const SCRIPT_LITE := preload("res://addons/savestate/save_manager.gd")
const SCRIPT_LITE_PATH := "res://addons/savestate/save_manager.gd"
const SCRIPT_PRO_PATH := "res://addons/savestate_pro/pro_manager.gd"

var _tabs: TabContainer
var _list_main: ItemList
var _list_backup: ItemList
var _main_paths: PackedStringArray = PackedStringArray()
var _backup_paths: PackedStringArray = PackedStringArray()
var _rename_input: LineEdit
var _rename_btn: Button
var _hex: TextEdit
var _json: TextEdit
var _show_advanced: CheckBox
var _hint: Label
var _manager_status: Label
var _feature_strip: Control
var _feature_body: Control
var _feature_toggle: Button
var _thumb: TextureRect
var _info_file: Label
var _info_path: Label
var _info_size: Label
var _info_modified: Label
var _info_schema: Label
var _info_format: Label
var _info_security: Label
var _info_backup: Label
var _info_counts: Label
var _toast: Label
## Editor-only: autoload is often not mounted under [code]/root[/code] while the editor runs; we mirror it for inspect/write.
var _cached_tool_manager: SaveManagerBase = null

var _data_path: String = ""
var _data_flat: Dictionary = {}
var _data_original_flat: Dictionary = {}
var _data_pending: Dictionary = {}
var _data_search: LineEdit
var _data_tree: Tree
var _data_status: Label
var _data_pending_label: Label
var _data_live_sync: CheckBox
var _data_apply_btn: Button
var _data_discard_btn: Button
var _data_pro_banner: Label

var _cfg_json: CheckBox
var _cfg_backup: CheckBox
var _cfg_enc: Label
var _cfg_key_status: Label
var _cfg_gen_keys: Button
var _cfg_pro_hint: Label
var _dbg_plugin: Object = null
var _pro_enabled: bool = false


func _ready() -> void:
	set_name("SaveStateSaveBrowser")
	add_to_group("savestate_save_browser")
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(v)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)

	_build_explorer_tab()
	_build_data_tab()
	_build_config_tab()

	call_deferred("_on_refresh")
	call_deferred("_sync_config_from_manager")


func set_debugger_plugin(p: Object) -> void:
	_dbg_plugin = p


func _log(msg: String) -> void:
	print("%s %s" % [LOG_PREFIX, msg])


func _exit_tree() -> void:
	if _cached_tool_manager != null:
		_log("disposing editor tool manager mirror")
		_cached_tool_manager.queue_free()
		_cached_tool_manager = null


func _build_explorer_tab() -> void:
	var panel := PanelContainer.new()
	panel.name = "Explorer"
	_tabs.add_child(panel)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(root)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.text = "Explorer: click a save to preview • double-click to open Data • thumbnails from Pro async saves."
	root.add_child(_hint)

	# Keep the Explorer top clean: Pro details live in badges + Config.
	_feature_body = null
	_feature_strip = null
	_feature_toggle = null

	_manager_status = Label.new()
	_manager_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_manager_status.add_theme_font_size_override("font_size", 12)
	_manager_status.text = "SaveManager: resolving…"
	root.add_child(_manager_status)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(_on_refresh)
	bar.add_child(refresh)
	var restore_btn := Button.new()
	restore_btn.text = "Restore from .bak"
	restore_btn.tooltip_text = "Renames .bak over the main save (consumes .bak)."
	restore_btn.pressed.connect(_on_restore_backup)
	bar.add_child(restore_btn)
	var del_btn := Button.new()
	del_btn.text = "Delete selected"
	del_btn.pressed.connect(_on_delete_selected)
	bar.add_child(del_btn)
	bar.add_spacer(false)
	_rename_input = LineEdit.new()
	_rename_input.placeholder_text = "Rename slot…"
	_rename_input.custom_minimum_size.x = 180
	_rename_input.text_submitted.connect(func(_t: String) -> void:
		_on_rename_pressed()
	)
	bar.add_child(_rename_input)
	_rename_btn = Button.new()
	_rename_btn.text = "Rename"
	_rename_btn.tooltip_text = "Renames the selected slot file. If a .bak and thumbnail exist, they are renamed too."
	_rename_btn.pressed.connect(_on_rename_pressed)
	bar.add_child(_rename_btn)
	bar.add_spacer(false)
	var open_folder := Button.new()
	open_folder.text = "Open save folder"
	open_folder.tooltip_text = "Opens the save directory in your OS file explorer."
	open_folder.pressed.connect(_on_open_save_folder)
	bar.add_child(open_folder)

	var vsp := VSplitContainer.new()
	vsp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(vsp)

	var main := HSplitContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vsp.add_child(main)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(left)

	var sec_main := Label.new()
	sec_main.text = "Main saves"
	sec_main.add_theme_font_size_override("font_size", 12)
	sec_main.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	left.add_child(sec_main)

	_list_main = ItemList.new()
	_list_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_main.custom_minimum_size = Vector2(260, 120)
	_list_main.allow_reselect = true
	_list_main.select_mode = ItemList.SELECT_SINGLE
	_list_main.item_selected.connect(_on_explorer_main_selected)
	_list_main.item_activated.connect(func(idx: int) -> void:
		_on_explorer_activated(_list_main, idx)
	)
	left.add_child(_list_main)

	var sep := HSeparator.new()
	left.add_child(sep)

	var sec_bak := Label.new()
	sec_bak.text = "Backups (.bak)"
	sec_bak.add_theme_font_size_override("font_size", 12)
	sec_bak.add_theme_color_override("font_color", Color(1.0, 0.8, 0.55))
	left.add_child(sec_bak)

	_list_backup = ItemList.new()
	_list_backup.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_backup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_backup.custom_minimum_size = Vector2(260, 100)
	_list_backup.allow_reselect = true
	_list_backup.select_mode = ItemList.SELECT_SINGLE
	_list_backup.item_selected.connect(_on_explorer_backup_selected)
	_list_backup.item_activated.connect(func(idx: int) -> void:
		_on_explorer_activated(_list_backup, idx)
	)
	left.add_child(_list_backup)

	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)

	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(320, 180)
	_thumb.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(_thumb)

	var info := PanelContainer.new()
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(info)

	var info_v := VBoxContainer.new()
	info.add_child(info_v)
	var info_title := Label.new()
	info_title.text = "Save info"
	info_title.add_theme_font_size_override("font_size", 14)
	info_v.add_child(info_title)

	var info_rows := VBoxContainer.new()
	info_rows.add_theme_constant_override("separation", 4)
	info_v.add_child(info_rows)

	_info_file = _make_meta_value("-")
	_add_info_row(info_rows, "File", _info_file)
	_info_path = _make_meta_value("-")
	_add_info_row(info_rows, "Path", _info_path)
	_info_size = _make_meta_value("-")
	_add_info_row(info_rows, "Size", _info_size)
	_info_modified = _make_meta_value("-")
	_add_info_row(info_rows, "Modified", _info_modified)
	_info_schema = _make_meta_value("-")
	_add_info_row(info_rows, "Schema", _info_schema)
	_info_format = _make_meta_value("-")
	_add_info_row(info_rows, "Format", _info_format)
	_info_security = _make_meta_value("-")
	_add_info_row(info_rows, "Security", _info_security)
	_info_backup = _make_meta_value("-")
	_add_info_row(info_rows, "Backup", _info_backup)

	var actions := HBoxContainer.new()
	info_v.add_child(actions)
	var open_file := Button.new()
	open_file.text = "Reveal file"
	open_file.tooltip_text = "Opens the save folder in your OS file explorer."
	open_file.pressed.connect(_on_reveal_selected_file)
	actions.add_child(open_file)
	actions.add_spacer(false)
	var jump_data := Button.new()
	jump_data.text = "Open in Data"
	jump_data.tooltip_text = "Switches to Data tab for the selected save."
	jump_data.pressed.connect(_on_open_selected_in_data)
	actions.add_child(jump_data)

	_info_counts = Label.new()
	_info_counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_counts.text = ""
	info_v.add_child(_info_counts)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 220)
	vsp.add_child(split)

	_hex = TextEdit.new()
	_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hex.editable = false
	_hex.placeholder_text = "Hex (truncated)"
	split.add_child(_hex)

	_json = TextEdit.new()
	_json.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_json.editable = false
	_json.placeholder_text = "Decoded JSON / status"
	split.add_child(_json)

	var adv_row := HBoxContainer.new()
	root.add_child(adv_row)
	_show_advanced = CheckBox.new()
	_show_advanced.text = "Advanced (show hex)"
	_show_advanced.button_pressed = false
	_show_advanced.toggled.connect(func(on: bool) -> void:
		_hex.visible = on
	)
	adv_row.add_child(_show_advanced)
	adv_row.add_spacer(false)
	var adv_hint := Label.new()
	adv_hint.text = "Hex is for debugging file bytes."
	adv_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	adv_row.add_child(adv_hint)

	_hex.visible = false

	_toast = Label.new()
	_toast.text = ""
	_toast.visible = false
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", 12)
	root.add_child(_toast)


func _add_info_row(parent: VBoxContainer, key: String, value_label: Label) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var k := Label.new()
	k.text = key
	k.custom_minimum_size.x = 96
	k.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
	row.add_child(k)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(value_label)
	parent.add_child(row)


func _make_meta_value(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", Color(0.92, 0.92, 0.93))
	return l


func _set_info_blank() -> void:
	if _info_file != null:
		_info_file.text = "-"
	if _info_path != null:
		_info_path.text = "-"
	if _info_size != null:
		_info_size.text = "-"
	if _info_modified != null:
		_info_modified.text = "-"
	if _info_schema != null:
		_info_schema.text = "-"
	if _info_format != null:
		_info_format.text = "-"
	if _info_security != null:
		_info_security.text = "-"
	if _info_backup != null:
		_info_backup.text = "-"


func _fmt_bytes(n: int) -> String:
	if n < 1024:
		return "%d B" % n
	var k := float(n) / 1024.0
	if k < 1024.0:
		return "%.1f KiB" % k
	var m := k / 1024.0
	if m < 1024.0:
		return "%.1f MiB" % m
	return "%.1f GiB" % (m / 1024.0)


func _format_time_ago(unix_time: int) -> String:
	if unix_time <= 0:
		return "-"
	var now := int(Time.get_unix_time_from_system())
	var d := maxi(0, now - unix_time)
	if d < 10:
		return "just now"
	if d < 60:
		return "%ds ago" % d
	var m := d / 60
	if m < 60:
		return "%dm ago" % m
	var h := m / 60
	if h < 48:
		return "%dh ago" % h
	var days := h / 24
	return "%dd ago" % days


func _toast_show(msg: String, kind: String = "ok") -> void:
	if _toast == null:
		return
	_toast.visible = true
	_toast.text = msg
	var c := Color(0.75, 1.0, 0.75)
	if kind == "warn":
		c = Color(1.0, 0.95, 0.6)
	elif kind == "err":
		c = Color(1.0, 0.7, 0.7)
	_toast.add_theme_color_override("font_color", c)
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(func() -> void:
		if is_instance_valid(_toast):
			_toast.visible = false
	)


func _try_get_editor_icon(name: String) -> Texture2D:
	if has_theme_icon(name, "EditorIcons"):
		return get_theme_icon(name, "EditorIcons")
	return null


func _health_for_path(path: String) -> Dictionary:
	var sm := _get_save_manager()
	if sm == null:
		return {}
	return sm.debug_health_for_path(path)


func _apply_list_row_status(list: ItemList, i: int, path: String) -> void:
	var st := _health_for_path(path)
	var tool := PackedStringArray()
	tool.append("Size: %s" % _fmt_bytes(int(st.get("raw_size", 0))))
	tool.append("Modified: %s" % _format_time_ago(int(st.get("modified_unix", 0))))
	var enc_outer := bool(st.get("encrypted_outer", false))
	var verified: Variant = st.get("verified", null)
	var ver_txt := "Unknown"
	if typeof(verified) == TYPE_BOOL:
		ver_txt = "OK" if bool(verified) else "FAILED"
	var has_backup := FileAccess.file_exists(path.trim_suffix(".bak") + ".bak")
	tool.append("Encrypted: %s" % ("Yes" if enc_outer else "No"))
	tool.append("Verified (HMAC): %s" % ver_txt)
	tool.append("Schema: %s (current %s)" % [str(st.get("schema_version", 0)), str(st.get("current_schema_version", 0))])
	tool.append("Backup (.bak): %s" % ("Present" if has_backup else "Missing"))
	tool.append("Keys: %s" % ("Present" if bool(st.get("keys_present", false)) else "Missing"))
	tool.append("Saveables: %s" % (str(st.get("saveables_count", 0)) if bool(st.get("has_saveables", false)) else "none"))
	list.set_item_tooltip(i, "\n".join(tool))

	var icon: Texture2D = null
	if bool(st.get("ok", false)) == false and int(st.get("error", OK)) != OK:
		icon = _try_get_editor_icon("StatusError")
	elif enc_outer:
		var v: Variant = st.get("verified", null)
		if typeof(v) == TYPE_BOOL and bool(v):
			icon = _try_get_editor_icon("StatusSuccess")
		else:
			icon = _try_get_editor_icon("Lock")
	if icon == null and bool(st.get("needs_migration", false)):
		icon = _try_get_editor_icon("StatusWarning")
	if icon == null and not has_backup:
		icon = _try_get_editor_icon("StatusWarning")
	if icon != null:
		list.set_item_icon(i, icon)

	# Visual row differentiation (primary vs backup) + health strip via background color.
	var is_backup := path.ends_with(".bak")
	var base := Color(0.17, 0.17, 0.18) if is_backup else Color(0.13, 0.13, 0.14)
	var bg := base
	var err := int(st.get("error", OK))
	# reuse enc/verified from above
	var needs_mig := bool(st.get("needs_migration", false))
	if bool(st.get("ok", false)) == false and err != OK:
		bg = Color(0.28, 0.14, 0.14) # red-ish
	elif enc_outer and typeof(verified) == TYPE_BOOL and bool(verified):
		bg = Color(0.14, 0.22, 0.14) # green-ish
	elif needs_mig or not has_backup or (enc_outer and typeof(verified) == TYPE_BOOL and not bool(verified)):
		bg = Color(0.24, 0.20, 0.12) # yellow-ish
	list.set_item_custom_bg_color(i, bg)


func _build_data_tab() -> void:
	var panel := PanelContainer.new()
	panel.name = "Data"
	_tabs.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)

	var title := Label.new()
	title.text = "Edit inner save payload (decoded JSON). Nested keys flattened with dot paths. Double-click a file in Explorer to jump here."
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(title)

	_data_pro_banner = Label.new()
	_data_pro_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_data_pro_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_data_pro_banner.visible = false
	_data_pro_banner.text = "Pro feature: editing and committing changes is available in SaveState Pro. In Lite you can inspect saves, but edits are disabled."
	vb.add_child(_data_pro_banner)

	_data_status = Label.new()
	_data_status.text = "Select a .bin / .json in Explorer first (or double-click it)."
	vb.add_child(_data_status)

	var row := HBoxContainer.new()
	vb.add_child(row)
	_data_pending_label = Label.new()
	_data_pending_label.text = "Pending changes: 0"
	row.add_child(_data_pending_label)
	row.add_spacer(false)
	_data_live_sync = CheckBox.new()
	_data_live_sync.text = "Live Sync"
	_data_live_sync.tooltip_text = "Advanced: when enabled and a game is running with debugger connected, Commit will also patch the running game state."
	_data_live_sync.toggled.connect(_on_live_sync_toggled)
	row.add_child(_data_live_sync)

	_data_search = LineEdit.new()
	_data_search.placeholder_text = "Search keys…"
	_data_search.text_changed.connect(_on_data_search_changed)
	vb.add_child(_data_search)

	_data_tree = Tree.new()
	_data_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_data_tree.custom_minimum_size = Vector2(0, 200)
	_data_tree.columns = 2
	_data_tree.column_titles_visible = true
	_data_tree.set_column_title(0, "Key")
	_data_tree.set_column_title(1, "Value")
	_data_tree.set_column_expand(0, true)
	_data_tree.set_column_expand(1, true)
	_data_tree.hide_root = true
	_data_tree.item_edited.connect(_on_data_tree_edited)
	vb.add_child(_data_tree)

	var apply := Button.new()
	_data_apply_btn = apply
	apply.text = "Commit changes"
	apply.tooltip_text = "Writes the current tree back through SaveManager. If Live Sync is ON and a game is connected, also applies the patch at runtime."
	apply.pressed.connect(_on_data_apply)
	vb.add_child(apply)

	_data_discard_btn = Button.new()
	_data_discard_btn.text = "Discard changes"
	_data_discard_btn.disabled = true
	_data_discard_btn.pressed.connect(_on_data_discard)
	vb.add_child(_data_discard_btn)


func _build_config_tab() -> void:
	var panel := PanelContainer.new()
	panel.name = "Config"
	_tabs.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)

	var l := Label.new()
	l.text = "These settings mirror the SaveManager autoload. They apply when you run the game and when this dock reads or writes saves in the editor."
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)

	_cfg_json = CheckBox.new()
	_cfg_json.text = "Use human-readable JSON files (.json) instead of compact binary (.bin)"
	_cfg_json.tooltip_text = "JSON: easy to inspect in a text editor and diff in version control — larger files and slightly slower. Binary: smaller and faster — default for shipped games. Toggle for debugging or content pipelines; existing files keep their extension until you save again."
	_cfg_json.toggled.connect(_on_cfg_json_toggled)
	vb.add_child(_cfg_json)

	_cfg_backup = CheckBox.new()
	_cfg_backup.text = "Keep a rolling backup (.bak) next to the main file on each save"
	_cfg_backup.tooltip_text = "Before overwriting a slot, the previous file is copied to the same name with .bak. Lets players recover from bad saves or bad edits. On by default in Lite and Pro; turn off only if you do not want .bak files."
	_cfg_backup.toggled.connect(_on_cfg_backup_toggled)
	vb.add_child(_cfg_backup)

	_cfg_enc = Label.new()
	_cfg_enc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cfg_enc.text = "Encryption (Pro): AES-256 wraps file bytes; HMAC proves the file was not edited outside your game. Use when you want to discourage casual tampering — not a substitute for server authority. Generate keys once per project and ship them only in trusted builds."
	vb.add_child(_cfg_enc)

	_cfg_gen_keys = Button.new()
	_cfg_gen_keys.text = "Generate keys (AES + HMAC)"
	_cfg_gen_keys.tooltip_text = "Creates random keys and stores them in Project Settings (savestate_pro/aes_key_hex and savestate_pro/hmac_key_hex), then turns encryption on. Anyone with your project or exported pck can extract keys — this deters casual edits, not determined reverse engineers."
	_cfg_gen_keys.pressed.connect(_on_generate_keys_pressed)
	vb.add_child(_cfg_gen_keys)

	_cfg_key_status = Label.new()
	_cfg_key_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cfg_key_status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_cfg_key_status.text = ""
	vb.add_child(_cfg_key_status)

	_cfg_pro_hint = Label.new()
	_cfg_pro_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cfg_pro_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_cfg_pro_hint.text = ""
	vb.add_child(_cfg_pro_hint)

	var btn := Button.new()
	btn.text = "Re-detect SaveManager (Lite / Pro)"
	btn.tooltip_text = "If you toggle the Pro plugin on/off while the editor is open, click this to refresh which script the dock is mirroring."
	btn.pressed.connect(_on_redetect_manager_pressed)
	vb.add_child(btn)


func _on_redetect_manager_pressed() -> void:
	_reset_editor_tool_manager_mirror()
	_sync_config_from_manager()


func _reset_editor_tool_manager_mirror() -> void:
	if _cached_tool_manager != null:
		_cached_tool_manager.queue_free()
		_cached_tool_manager = null


func _sync_config_from_manager() -> void:
	# If Pro was enabled/disabled after this dock was created, our editor-mirror may be stale.
	# Prefer re-creating the mirror when it doesn't match current ProjectSettings.
	var desired_path := _resolve_autoload_script_path()
	if _cached_tool_manager != null:
		var cur_script := _cached_tool_manager.get_script()
		var cur_path := (str(cur_script.resource_path) if cur_script != null else "")
		if cur_path != desired_path:
			_reset_editor_tool_manager_mirror()

	var sm := _get_save_manager()
	if sm == null:
		return
	_pro_enabled = _is_pro_manager(sm)
	_cfg_json.button_pressed = sm.use_json
	_cfg_backup.button_pressed = sm.backup_on_commit
	_cfg_backup.disabled = false
	if _data_pro_banner != null:
		_data_pro_banner.visible = not _pro_enabled
	if _data_apply_btn != null:
		_data_apply_btn.disabled = not _pro_enabled
	if _data_discard_btn != null:
		_data_discard_btn.disabled = not _pro_enabled
	if _data_live_sync != null:
		_data_live_sync.disabled = (not _pro_enabled) or (_dbg_plugin == null)
	if _cfg_gen_keys != null:
		_cfg_gen_keys.disabled = not _pro_enabled
	if _cfg_pro_hint != null:
		if _pro_enabled:
			_cfg_pro_hint.text = "Pro unlocked: encryption + verification, Live Sync, Saveable inspector, async thumbnails."
		else:
			_cfg_pro_hint.text = "Lite mode: Pro-only controls are shown but disabled. Enable the SaveState Pro plugin to unlock them."
	_update_key_status()
	if _data_tree != null:
		_refill_data_tree()


func _update_key_status() -> void:
	if _cfg_key_status == null:
		return
	var aes_hex := str(ProjectSettings.get_setting("savestate_pro/aes_key_hex", ""))
	var hmac_hex := str(ProjectSettings.get_setting("savestate_pro/hmac_key_hex", ""))
	var has_aes := aes_hex.length() >= 64
	var has_hmac := hmac_hex.length() >= 64
	_cfg_key_status.text = "Keys: %s" % ("Installed" if (has_aes and has_hmac) else "Missing (click Generate keys)")


func _on_generate_keys_pressed() -> void:
	var crypto := Crypto.new()
	var aes := crypto.generate_random_bytes(32)
	var hmac := crypto.generate_random_bytes(32)
	var aes_hex := aes.hex_encode()
	var hmac_hex := hmac.hex_encode()
	ProjectSettings.set_setting("savestate_pro/aes_key_hex", aes_hex)
	ProjectSettings.set_setting("savestate_pro/hmac_key_hex", hmac_hex)
	ProjectSettings.set_setting("savestate_pro/encryption_enabled", true)
	ProjectSettings.save()
	_update_key_status()
	_toast_show("Keys generated. Verification is now active for encrypted saves.", "ok")


func _is_pro_manager(sm: SaveManagerBase) -> bool:
	return sm.get_script() != null and str(sm.get_script().resource_path).contains("savestate_pro")


func _on_cfg_json_toggled(pressed: bool) -> void:
	var sm := _get_save_manager()
	if sm:
		sm.use_json = pressed


func _on_cfg_backup_toggled(pressed: bool) -> void:
	var sm := _get_save_manager()
	if sm:
		sm.backup_on_commit = pressed


func _get_save_root() -> String:
	var sm := _get_save_manager()
	if sm != null:
		var r := str(sm.save_root).strip_edges()
		if not r.is_empty():
			return r
	return "user://savestate"


func _on_refresh() -> void:
	_list_main.clear()
	_list_backup.clear()
	_main_paths.clear()
	_backup_paths.clear()
	var root := _get_save_root()
	_hint.text = "Scanning: %s — click to preview hex/JSON; double-click opens Data tab." % root
	_set_info_blank()
	_thumb.texture = null

	var abs_root := ProjectSettings.globalize_path(root)
	DirAccess.make_dir_recursive_absolute(abs_root)

	var dir := DirAccess.open(root)
	if dir == null:
		_hex.text = "Cannot open: %s" % root
		return

	dir.list_dir_begin()
	var mains: Array[String] = []
	var baks: Array[String] = []
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and _is_listed_save_file(fn):
			var p := root.path_join(fn)
			if fn.ends_with(".bak"):
				baks.append(p)
			else:
				mains.append(p)
		fn = dir.get_next()
	dir.list_dir_end()

	mains.sort()
	baks.sort()

	for p in mains:
		_main_paths.append(p)
		var idx := _list_main.add_item(p.get_file())
		_apply_list_row_status(_list_main, idx, p)

	for p in baks:
		_backup_paths.append(p)
		var idxb := _list_backup.add_item(p.get_file())
		_apply_list_row_status(_list_backup, idxb, p)

	var total := mains.size() + baks.size()
	_hint.text = "%s — %d save(s), %d backup(s). Click = preview; double-click = Data tab." % [root, mains.size(), baks.size()]
	_log("refresh scan root=%s count=%d" % [root, total])
	var sm := _get_save_manager()
	if sm != null:
		_log("refresh using manager save_root=%s use_json=%s" % [sm.save_root, str(sm.use_json)])

	if total == 0:
		_json.text = "No save files. Run the game and call SaveManager.persist() or persist_async()."
		return

	# Auto-select first main save to populate the info panel.
	if mains.size() > 0:
		_list_backup.deselect_all()
		_list_main.select(0)
		_on_explorer_main_selected(0)


func _is_listed_save_file(fn: String) -> bool:
	if fn.ends_with(".bin.bak") or fn.ends_with(".json.bak"):
		return true
	if fn.ends_with(".tmp"):
		return false
	if fn.ends_with(".jpg") or fn.ends_with(".png"):
		return false
	return fn.ends_with(".bin") or fn.ends_with(".json")


func _get_selected_save_path() -> String:
	var smain := _list_main.get_selected_items()
	if not smain.is_empty():
		var i := int(smain[0])
		if i >= 0 and i < _main_paths.size():
			return _main_paths[i]
	var sbak := _list_backup.get_selected_items()
	if not sbak.is_empty():
		var j := int(sbak[0])
		if j >= 0 and j < _backup_paths.size():
			return _backup_paths[j]
	return ""


func _on_explorer_main_selected(index: int) -> void:
	_list_backup.deselect_all()
	if index < 0 or index >= _main_paths.size():
		return
	_on_explorer_pick(_main_paths[index], _list_main, index)


func _on_explorer_backup_selected(index: int) -> void:
	_list_main.deselect_all()
	if index < 0 or index >= _backup_paths.size():
		return
	_on_explorer_pick(_backup_paths[index], _list_backup, index)


func _on_explorer_activated(which: ItemList, index: int) -> void:
	var path := ""
	if which == _list_main and index >= 0 and index < _main_paths.size():
		path = _main_paths[index]
	elif which == _list_backup and index >= 0 and index < _backup_paths.size():
		path = _backup_paths[index]
	if path.is_empty():
		return
	_log("explorer item_activated file=%s" % path)
	_on_explorer_pick(path, which, index)
	if _tabs != null:
		_tabs.current_tab = 1
		_log("switched to Data tab (double-click / Enter)")


func _on_explorer_pick(path: String, source_list: ItemList, row_index: int) -> void:
	var sm := _get_save_manager()
	if sm == null:
		_log("explorer select: SaveManager still null (unexpected)")
		_hex.text = ""
		_json.text = "SaveManager not found."
		_thumb.texture = null
		_set_info_blank()
		return

	_log("explorer select: %s" % path)
	_apply_list_row_status(source_list, row_index, path)
	_update_info_panel_for_path(path)
	var info: Dictionary = sm.debug_inspect_save_path(path)
	_log(
		"inspect: ok=%s raw_size=%s thumb_path=%s"
		% [str(info.get("ok", false)), str(info.get("raw_size", "?")), str(info.get("thumb_path", ""))]
	)
	_hex.text = str(info.get("hex_preview", ""))
	if info.get("ok", false):
		_json.text = str(info.get("json_preview", ""))
	else:
		_json.text = "Parse failed (encrypted saves need keys). %s" % str(info.get("error", 0))

	var tp := str(info.get("thumb_path", ""))
	if not tp.is_empty() and FileAccess.file_exists(tp):
		var bytes := FileAccess.get_file_as_bytes(tp)
		if bytes.is_empty():
			_log("thumbnail: empty bytes %s" % tp)
			_thumb.texture = null
		else:
			var img := Image.new()
			if img.load_jpg_from_buffer(bytes) == OK:
				_thumb.texture = ImageTexture.create_from_image(img)
				_log("thumbnail: loaded %s (%d bytes)" % [tp, bytes.size()])
			else:
				_log("thumbnail: load_jpg_from_buffer failed %s" % tp)
				_thumb.texture = null
	else:
		if not tp.is_empty():
			_log("thumbnail: no file at %s" % tp)
		_thumb.texture = null

	_data_path = path
	_populate_data_tab(info)


func _update_info_panel_for_path(path: String) -> void:
	if _info_file == null:
		return
	_info_file.text = path.get_file()
	_info_path.text = path
	if _rename_input != null:
		_rename_input.text = path.get_file().get_basename()
	var st := _health_for_path(path)
	_info_size.text = _fmt_bytes(int(st.get("raw_size", 0)))
	var mt := int(st.get("modified_unix", 0))
	_info_modified.text = "%s (%s)" % [_format_time_ago(mt), (Time.get_datetime_string_from_unix_time(mt, true) if mt > 0 else "-")]
	var sc := int(st.get("schema_version", 0))
	var cur := int(st.get("current_schema_version", 0))
	var mig := bool(st.get("needs_migration", false))
	_info_schema.text = "%d%s (current %d)" % [sc, " ⚠" if mig else "", cur]
	var flags := int(st.get("flags", 0))
	var is_json := (flags & SaveManagerBase.FLAG_JSON) != 0
	var wrapped := bool(st.get("encrypted_outer", false))
	_info_format.text = "%s%s" % ["JSON" if is_json else "BIN", " + Encrypted wrapper" if wrapped else ""]
	var keys_present := bool(st.get("keys_present", false))
	var verified: Variant = st.get("verified", null)
	var ver_txt := "Unknown"
	if typeof(verified) == TYPE_BOOL:
		ver_txt = "OK" if bool(verified) else "FAILED"
	if wrapped:
		_info_security.text = "Encrypted: Yes • Keys: %s • HMAC: %s" % ["Present" if keys_present else "Missing", ver_txt]
	else:
		_info_security.text = "Encrypted: No"
	var has_bak := FileAccess.file_exists(path.trim_suffix(".bak") + ".bak")
	_info_backup.text = "Present" if has_bak else "Missing"
	if _info_counts != null:
		var kc := int(st.get("key_count", 0))
		var sv := int(st.get("saveables_count", 0))
		_info_counts.text = "Contents: %d top-level keys • Saveables: %d" % [kc, sv]


func _on_open_save_folder() -> void:
	var root := _get_save_root()
	var abs := ProjectSettings.globalize_path(root)
	_log("open save folder: %s" % abs)
	OS.shell_open(abs)


func _on_reveal_selected_file() -> void:
	var path := _get_selected_save_path()
	if path.is_empty():
		return
	var abs := ProjectSettings.globalize_path(path.get_base_dir())
	_log("reveal selected file folder: %s" % abs)
	OS.shell_open(abs)


func _on_open_selected_in_data() -> void:
	var path := _get_selected_save_path()
	if path.is_empty():
		path = _data_path
	if path.is_empty():
		return
	if _tabs != null:
		_tabs.current_tab = 1


func _populate_data_tab(info: Dictionary) -> void:
	_data_tree.clear()
	_data_flat.clear()
	_data_original_flat.clear()
	_data_pending.clear()
	_update_pending_ui()
	if not info.get("ok", false):
		_data_status.text = "Cannot edit: parse failed (try JSON mode or disable encryption for editor tools)."
		return

	var inner: Dictionary = info.get("inner_dict", {}) as Dictionary
	if inner.is_empty() and info.has("json_preview"):
		var parsed: Variant = JSON.parse_string(str(info.get("json_preview", "{}")))
		if parsed is Dictionary:
			inner = parsed
	_data_flat = _flatten_for_editor(inner)
	_data_original_flat = _data_flat.duplicate(true)
	_data_status.text = "Editing: %s (%d keys)" % [_data_path.get_file(), _data_flat.size()]
	_refill_data_tree()


func _flatten_for_editor(d: Dictionary, prefix: String = "") -> Dictionary:
	var out := {}
	for k in d:
		var ks := str(k)
		var path := ks if prefix.is_empty() else prefix + "." + ks
		var v: Variant = d[k]
		if v is Dictionary:
			var sub := _flatten_for_editor(v, path)
			for sk in sub:
				out[sk] = sub[sk]
		elif v is Array:
			out[path] = JSON.stringify(v)
		else:
			out[path] = v
	return out


func _refill_data_tree() -> void:
	_data_tree.clear()
	var root := _data_tree.create_item()
	var q := _data_search.text.strip_edges().to_lower()
	var keys: Array = _data_flat.keys()
	keys.sort()
	var allow_edit := _pro_enabled
	for k in keys:
		if not q.is_empty() and not str(k).to_lower().contains(q):
			continue
		var it := _data_tree.create_item(root)
		it.set_text(0, str(k))
		it.set_text(1, _value_to_edit_string(_data_flat[k]))
		it.set_editable(0, false)
		it.set_editable(1, allow_edit)


func _value_to_edit_string(v: Variant) -> String:
	var t := typeof(v)
	if t == TYPE_BOOL or t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_STRING:
		return str(v)
	return JSON.stringify(v)


func _on_data_search_changed(_t: String) -> void:
	_refill_data_tree()


func _on_data_tree_edited() -> void:
	var it := _data_tree.get_edited()
	if it == null:
		return
	if _data_tree.get_edited_column() != 1:
		return
	if not _pro_enabled:
		_toast_show("Editing is a Pro feature (Lite is read-only).", "warn")
		var k0 := str(it.get_text(0))
		if _data_flat.has(k0):
			it.set_text(1, _value_to_edit_string(_data_flat[k0]))
		return
	var k := str(it.get_text(0))
	var vstr := str(it.get_text(1))
	var v := _parse_value_string(vstr)
	_data_flat[k] = v
	var had_orig := _data_original_flat.has(k)
	var orig := _data_original_flat.get(k, null)
	if (not had_orig and v != null) or (had_orig and orig != v):
		_data_pending[k] = v
	else:
		_data_pending.erase(k)
	_update_pending_ui()


func _update_pending_ui() -> void:
	if _data_pending_label != null:
		_data_pending_label.text = "Pending changes: %d" % _data_pending.size()
	if _data_discard_btn != null:
		_data_discard_btn.disabled = _data_pending.is_empty()
	if _data_apply_btn != null:
		_data_apply_btn.disabled = _data_pending.is_empty()


func _on_data_discard() -> void:
	if _data_original_flat.is_empty():
		return
	_data_flat = _data_original_flat.duplicate(true)
	_data_pending.clear()
	_update_pending_ui()
	_refill_data_tree()
	_toast_show("Discarded pending changes", "warn")


func _on_live_sync_toggled(on: bool) -> void:
	if _data_apply_btn != null:
		# Orange-ish when live mode on, neutral otherwise.
		if on:
			_data_apply_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
		else:
			_data_apply_btn.remove_theme_color_override("font_color")
	if on:
		_toast_show("Live Sync enabled", "warn")


func _parse_value_string(s: String) -> Variant:
	var t := s.strip_edges()
	if t == "true":
		return true
	if t == "false":
		return false
	if t.is_valid_int():
		return int(t)
	if t.is_valid_float():
		return float(t)
	var j: Variant = JSON.parse_string(t)
	if j != null:
		return j
	return t


func _on_data_apply() -> void:
	if _data_path.is_empty():
		_data_status.text = "No file selected."
		return
	var sm := _get_save_manager()
	if sm == null:
		_data_status.text = "SaveManager missing."
		return
	var inner := _unflatten_from_flat(_data_flat)
	_log("data apply: writing inner dict keys=%d path=%s" % [_data_flat.size(), _data_path])
	var err: Error = sm.write_inner_data_to_disk(_data_path, inner) as Error
	if err != OK:
		_log("data apply: FAILED %s" % error_string(err))
		_data_status.text = "Write failed: %s" % error_string(err)
		_toast_show("Write failed: %s" % error_string(err), "err")
		return
	_log("data apply: OK")
	_data_status.text = "Saved OK. Refresh Explorer to verify."
	_toast_show("Saved OK", "ok")
	if _data_live_sync != null and _data_live_sync.button_pressed and not _data_pending.is_empty():
		_try_send_live_patch(_data_pending)
	_data_original_flat = _data_flat.duplicate(true)
	_data_pending.clear()
	_update_pending_ui()
	_on_refresh()


func _try_send_live_patch(patch: Dictionary) -> void:
	if patch.is_empty():
		return
	if _dbg_plugin == null or not _dbg_plugin.has_method("send_kv_patch"):
		_toast_show("Live Sync: debugger plugin unavailable", "warn")
		return
	var ok: bool = bool(_dbg_plugin.call("send_kv_patch", patch))
	if ok:
		_toast_show("Live Sync: patched running game", "ok")
	else:
		_toast_show("Live Sync: no running game session", "warn")


func _unflatten_from_flat(flat: Dictionary) -> Dictionary:
	var root := {}
	for k in flat:
		var parts: PackedStringArray = str(k).split(".")
		var cur: Dictionary = root
		for i in range(parts.size()):
			var part := parts[i]
			if i == parts.size() - 1:
				cur[part] = flat[k]
			else:
				if not cur.has(part) or not (cur[part] is Dictionary):
					cur[part] = {}
				cur = cur[part]
	return root


func _on_restore_backup() -> void:
	var path := _get_selected_save_path()
	if path.is_empty():
		_json.text = "Select a file first."
		return
	var main_path := path
	if path.ends_with(".bak"):
		main_path = path.trim_suffix(".bak")
	if not FileAccess.file_exists(main_path + ".bak"):
		_json.text = "No .bak for this save."
		return
	var sm := _get_save_manager()
	var err: Error
	if sm != null:
		err = sm.restore_from_backup_file(main_path) as Error
	else:
		err = _restore_backup_files_direct(main_path)
	if err != OK:
		_json.text = "Restore failed: %s" % error_string(err)
		_toast_show("Restore failed: %s" % error_string(err), "err")
		return
	_json.text = "Restored from .bak."
	_toast_show("Restored from .bak", "ok")
	_on_refresh()


static func _restore_backup_files_direct(main_path: String) -> Error:
	var bak_path := main_path + ".bak"
	if not FileAccess.file_exists(bak_path):
		return ERR_FILE_NOT_FOUND
	if FileAccess.file_exists(main_path):
		var rm := DirAccess.remove_absolute(main_path)
		if rm != OK:
			return rm
	return DirAccess.rename_absolute(bak_path, main_path)


func _on_delete_selected() -> void:
	var path := _get_selected_save_path()
	if path.is_empty():
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		_toast_show("Deleted: %s" % path.get_file(), "warn")
	_on_refresh()


func _sanitize_new_slot_base_name(raw: String) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return ""
	# Prevent path traversal / invalid separators.
	if s.find("/") != -1 or s.find("\\") != -1 or s.find(":") != -1:
		return ""
	# Trim trailing dots/spaces (Windows).
	while s.ends_with(".") or s.ends_with(" "):
		s = s.left(s.length() - 1)
	return s


static func _move_file_absolute(from_abs: String, to_abs: String) -> Error:
	var err := DirAccess.rename_absolute(from_abs, to_abs)
	if err == OK:
		return OK
	# Fallback: copy + remove (useful if rename fails across volumes).
	err = DirAccess.copy_absolute(from_abs, to_abs)
	if err != OK:
		return err
	return DirAccess.remove_absolute(from_abs)


func _compute_rename_targets(selected_path: String, new_base: String) -> Dictionary:
	# Always rename the "slot" (main + optional .bak + optional thumbnail).
	var pick := selected_path
	var main_path := pick.trim_suffix(".bak") if pick.ends_with(".bak") else pick
	var dir := main_path.get_base_dir()
	var ext := main_path.get_extension()
	if ext.is_empty():
		ext = "bin"
	var new_main := dir.path_join("%s.%s" % [new_base, ext])
	var new_bak := new_main + ".bak"
	var old_bak := main_path + ".bak"
	return {
		"main_from": main_path,
		"main_to": new_main,
		"bak_from": old_bak,
		"bak_to": new_bak,
	}


func _try_rename_related_files(main_from: String, main_to: String) -> void:
	# Thumbnail file is optional; attempt to rename if present.
	var sm := _get_save_manager()
	if sm == null:
		return
	var info: Dictionary = sm.debug_inspect_save_path(main_from)
	var tp := str(info.get("thumb_path", ""))
	if tp.is_empty():
		return
	if not FileAccess.file_exists(tp):
		return
	var ext := tp.get_extension()
	if ext.is_empty():
		ext = "jpg"
	var new_thumb := main_to.get_basename() + "." + ext
	var from_abs := ProjectSettings.globalize_path(tp)
	var to_abs := ProjectSettings.globalize_path(new_thumb)
	_move_file_absolute(from_abs, to_abs)


func _on_rename_pressed() -> void:
	var selected := _get_selected_save_path()
	if selected.is_empty():
		_toast_show("Rename: select a save first.", "warn")
		return
	if _rename_input == null:
		return
	var base := _sanitize_new_slot_base_name(_rename_input.text)
	if base.is_empty():
		_toast_show("Rename: invalid name.", "err")
		return
	var targets := _compute_rename_targets(selected, base)
	var main_from := str(targets.get("main_from", ""))
	var main_to := str(targets.get("main_to", ""))
	var bak_from := str(targets.get("bak_from", ""))
	var bak_to := str(targets.get("bak_to", ""))
	if main_from == main_to:
		_toast_show("Rename: no change.", "warn")
		return
	var main_to_abs := ProjectSettings.globalize_path(main_to)
	var bak_to_abs := ProjectSettings.globalize_path(bak_to)
	if FileAccess.file_exists(main_to) or FileAccess.file_exists(bak_to):
		_toast_show("Rename: target already exists.", "err")
		return
	# Move main if it exists.
	if FileAccess.file_exists(main_from):
		var err := _move_file_absolute(ProjectSettings.globalize_path(main_from), main_to_abs)
		if err != OK:
			_toast_show("Rename failed: %s" % error_string(err), "err")
			return
	# Move backup if it exists.
	if FileAccess.file_exists(bak_from):
		var err2 := _move_file_absolute(ProjectSettings.globalize_path(bak_from), bak_to_abs)
		if err2 != OK:
			_toast_show("Rename: backup move failed: %s" % error_string(err2), "warn")
	# Move thumbnail if we can find it.
	_try_rename_related_files(main_from, main_to)

	# Keep Data tab pointing at the renamed file.
	if _data_path == selected or _data_path == main_from:
		_data_path = main_to
	_toast_show("Renamed to: %s" % main_to.get_file(), "ok")
	_on_refresh()


func _resolve_autoload_script_path() -> String:
	var v := ProjectSettings.get_setting("autoload/SaveManager", "")
	var s := str(v)
	if s.begins_with("*"):
		var uid_or := s.trim_prefix("*")
		var p := ResourceUID.uid_to_path(uid_or)
		if not p.is_empty():
			return p
		_log("uid_to_path failed for %s; falling back to Lite script" % uid_or)
		return SCRIPT_LITE_PATH
	return s


func _find_save_manager_under(n: Node) -> SaveManagerBase:
	if String(n.name) == "SaveManager" and n is SaveManagerBase:
		return n as SaveManagerBase
	for c in n.get_children():
		var r := _find_save_manager_under(c)
		if r != null:
			return r
	return null


func _create_editor_tool_manager() -> SaveManagerBase:
	var path := _resolve_autoload_script_path()
	_log("creating editor tool manager from %s" % path)
	var sc: GDScript = load(path) as GDScript
	if sc == null:
		_log("load(%s) failed; using Lite SaveManager" % path)
		sc = SCRIPT_LITE
	var mgr := sc.new() as SaveManagerBase
	if mgr == null:
		_log("script.new() failed; using SCRIPT_LITE")
		mgr = SCRIPT_LITE.new() as SaveManagerBase
	if _is_pro_manager(mgr):
		mgr.set("encryption_enabled", bool(ProjectSettings.get_setting("savestate_pro/encryption_enabled", false)))
		_log("Pro mirror encryption_enabled=%s" % str(mgr.get("encryption_enabled")))
	mgr._ready()
	_log(
		"editor tool manager ready path=%s save_root=%s use_json=%s backup_on_commit=%s"
		% [path, mgr.save_root, str(mgr.use_json), str(mgr.backup_on_commit)]
	)
	return mgr


func _get_or_create_editor_tool_manager() -> SaveManagerBase:
	if _cached_tool_manager != null:
		_update_manager_status_line(_cached_tool_manager, "editor mirror (no /root autoload)")
		return _cached_tool_manager
	_cached_tool_manager = _create_editor_tool_manager()
	_update_manager_status_line(_cached_tool_manager, "editor mirror (no /root autoload)")
	return _cached_tool_manager


func _update_manager_status_line(sm: SaveManagerBase, source: String) -> void:
	if _manager_status == null:
		return
	var kind := "Pro" if _is_pro_manager(sm) else "Lite"
	var enc := ""
	if _is_pro_manager(sm):
		enc = " enc=%s" % str(sm.get("encryption_enabled"))
	_manager_status.text = "SaveManager: %s • %s%s — %s" % [kind, sm.get_script().resource_path.get_file(), enc, source]


func _get_save_manager() -> SaveManagerBase:
	var st := Engine.get_main_loop() as SceneTree
	if st == null or st.root == null:
		_log("get_save_manager: SceneTree/root null → editor mirror")
		return _get_or_create_editor_tool_manager()
	var direct := st.root.get_node_or_null("SaveManager")
	if direct is SaveManagerBase:
		if _cached_tool_manager != null:
			_log("singleton available; dropping editor mirror cache")
			_cached_tool_manager.queue_free()
			_cached_tool_manager = null
		var sm0 := direct as SaveManagerBase
		_update_manager_status_line(sm0, "autoload /root/SaveManager")
		return sm0
	var found := _find_save_manager_under(st.root)
	if found != null:
		if _cached_tool_manager != null:
			_cached_tool_manager.queue_free()
			_cached_tool_manager = null
		_update_manager_status_line(found, "autoload %s" % str(found.get_path()))
		return found
	return _get_or_create_editor_tool_manager()
