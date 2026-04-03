@tool
extends Control
## Pro Save Browser: Explorer (files + thumbnail), Data (search + edit KV), Config (runtime toggles).

const SAVE_GROUP := "savestate_saveable"
const LOG_PREFIX := "[SaveState Pro | Save Browser]"
const DATA_COL_KEY := 0
const DATA_COL_SWATCH := 1
const DATA_COL_VALUE := 2
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
var _data_color_popup: PopupPanel
var _data_color_picker_widget: ColorPicker
var _data_editor_hints: Dictionary = {}
var _data_color_bound_key: String = ""
var _data_color_changing: bool = false

var _cfg_json: CheckBox
var _cfg_backup: CheckBox
var _cfg_enc: Label
var _cfg_key_status: Label
var _cfg_gen_keys: Button
var _cfg_redetect_btn: Button
var _cfg_pro_hint: Label
var _explorer_preview_block: Control
var _preview_toggle_btn: Button
var _raw_preview_expanded: bool = false
var _split_hex_json: HSplitContainer
var _explorer_adv_row: HBoxContainer
var _explorer_hsplit: HSplitContainer
var _explorer_vsplit: VSplitContainer
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
	call_deferred("_dock_apply_explorer_layout_defaults")


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
	bar.add_theme_constant_override("separation", 2)
	root.add_child(bar)
	bar.add_child(_make_icon_tool_button("Reload", "Refresh — rescan save folder", _on_refresh, "↻"))
	bar.add_child(
		_make_icon_tool_button(
			"Duplicate",
			"Backup selected — copy main save to .bak (pick a row under Main saves)",
			_on_backup_selected_now,
			"Bak"
		)
	)
	bar.add_child(
		_make_icon_tool_button(
			"History",
			"Restore from .bak — replaces main file with backup (consumes .bak)",
			_on_restore_backup,
			"Rest"
		)
	)
	bar.add_child(_make_icon_tool_button("Remove", "Delete selected file", _on_delete_selected, "Del"))
	bar.add_spacer(false)
	var rename_pair := HBoxContainer.new()
	rename_pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_pair.alignment = BoxContainer.ALIGNMENT_CENTER
	rename_pair.add_theme_constant_override("separation", 4)
	_rename_input = LineEdit.new()
	_rename_input.placeholder_text = "Rename slot…"
	_rename_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_input.text_submitted.connect(func(_t: String) -> void:
		_on_rename_pressed()
	)
	rename_pair.add_child(_rename_input)
	_rename_btn = Button.new()
	_rename_btn.text = "Rename"
	_rename_btn.custom_minimum_size.y = 28
	_rename_btn.tooltip_text = "Renames the selected slot file (.bak / .jpg move with it when present)."
	_rename_btn.pressed.connect(_on_rename_pressed)
	rename_pair.add_child(_rename_btn)
	_rename_input.custom_minimum_size.y = 28
	bar.add_child(rename_pair)
	bar.add_child(_make_icon_tool_button("FolderBrowse", "Open save folder in OS file manager", _on_open_save_folder, "Dir"))

	var vsp := VSplitContainer.new()
	_explorer_vsplit = vsp
	vsp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(vsp)

	var main := HSplitContainer.new()
	_explorer_hsplit = main
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
	_thumb.custom_minimum_size = Vector2(200, 112)
	_thumb.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(_thumb)

	var info_scroll := ScrollContainer.new()
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(info_scroll)

	var info := PanelContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(info)

	var info_v := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var export_json := Button.new()
	export_json.text = "Export JSON"
	export_json.tooltip_text = "Decodes the selected save (Pro: decrypts first) and writes a .json file next to it. SaveState Pro / itch.io."
	export_json.pressed.connect(_on_export_json_explorer)
	actions.add_child(export_json)

	_info_counts = Label.new()
	_info_counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_counts.text = ""
	info_v.add_child(_info_counts)

	_explorer_preview_block = VBoxContainer.new()
	_explorer_preview_block.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_explorer_preview_block.custom_minimum_size = Vector2(0, 120)
	vsp.add_child(_explorer_preview_block)

	_preview_toggle_btn = Button.new()
	_preview_toggle_btn.flat = true
	_preview_toggle_btn.focus_mode = Control.FOCUS_ACCESSIBILITY
	_preview_toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_toggle_btn.tooltip_text = "Expand to show decoded JSON and optional hex. Collapse to give file lists and save info more vertical room."
	_preview_toggle_btn.pressed.connect(_on_explorer_preview_toggle_pressed)
	_explorer_preview_block.add_child(_preview_toggle_btn)

	_split_hex_json = HSplitContainer.new()
	_split_hex_json.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split_hex_json.custom_minimum_size = Vector2(0, 140)
	_explorer_preview_block.add_child(_split_hex_json)

	_hex = TextEdit.new()
	_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hex.editable = false
	_hex.placeholder_text = "Hex (truncated)"
	_split_hex_json.add_child(_hex)

	_json = TextEdit.new()
	_json.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_json.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_json.editable = false
	_json.placeholder_text = "Decoded JSON / status"
	_split_hex_json.add_child(_json)

	_explorer_adv_row = HBoxContainer.new()
	_explorer_preview_block.add_child(_explorer_adv_row)
	_show_advanced = CheckBox.new()
	_show_advanced.text = "Advanced: show hex column"
	_show_advanced.button_pressed = false
	_show_advanced.toggled.connect(func(on: bool) -> void:
		_hex.visible = on
	)
	_explorer_adv_row.add_child(_show_advanced)
	_explorer_adv_row.add_spacer(false)
	var adv_hint := Label.new()
	adv_hint.text = "Hex is for debugging raw file bytes."
	adv_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_explorer_adv_row.add_child(adv_hint)

	_hex.visible = false
	_raw_preview_expanded = false
	_update_preview_toggle_label()
	_apply_preview_expanded_state()

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


func _make_icon_tool_button(icon_name: String, tooltip: String, cb: Callable, fallback_short: String = "") -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ACCESSIBILITY
	var ico := _try_get_editor_icon(icon_name)
	b.icon = ico
	b.tooltip_text = tooltip
	if ico == null:
		b.text = fallback_short if not fallback_short.is_empty() else tooltip.get_slice(" ", 0)
	b.pressed.connect(cb)
	return b


func _dock_apply_explorer_layout_defaults() -> void:
	var w := maxi(size.x, 480)
	var h := maxi(size.y, 320)
	if _explorer_hsplit != null:
		_explorer_hsplit.split_offset = clampi(int(w * 0.38), 220, 400)
	if _explorer_vsplit != null:
		_explorer_vsplit.split_offset = clampi(int(h * 0.52), 200, 520)


func _update_preview_toggle_label() -> void:
	if _preview_toggle_btn == null:
		return
	_preview_toggle_btn.text = (
		"▼ Raw preview (JSON / hex)" if _raw_preview_expanded else "▶ Raw preview (JSON / hex)"
	)


func _apply_preview_expanded_state() -> void:
	if _split_hex_json != null:
		_split_hex_json.visible = _raw_preview_expanded
	if _explorer_adv_row != null:
		_explorer_adv_row.visible = _raw_preview_expanded
	if _explorer_preview_block != null:
		_explorer_preview_block.custom_minimum_size = (
			Vector2(0, 120) if _raw_preview_expanded else Vector2(0, 36)
		)


func _on_explorer_preview_toggle_pressed() -> void:
	_raw_preview_expanded = not _raw_preview_expanded
	_update_preview_toggle_label()
	_apply_preview_expanded_state()


func _dock_swatch_texture(c: Color) -> Texture2D:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var border := x == 0 or y == 0 or x == n - 1 or y == n - 1
			img.set_pixel(x, y, Color(0.12, 0.12, 0.14, 1.0) if border else c)
	return ImageTexture.create_from_image(img)


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
	title.text = "Flat key–value editor • double-click a save in Explorer to open here."
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.modulate = Color(1, 1, 1, 0.78)
	vb.add_child(title)

	_data_pro_banner = Label.new()
	_data_pro_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_data_pro_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_data_pro_banner.visible = false
	_data_pro_banner.text = "Pro feature: editing and committing changes is available in SaveState Pro. In Lite you can inspect saves, but edits are disabled."
	vb.add_child(_data_pro_banner)

	_data_status = Label.new()
	_data_status.modulate = Color(1, 1, 1, 0.88)
	_data_status.text = "Select a .bin / .json in Explorer first (or double-click it)."
	vb.add_child(_data_status)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	vb.add_child(action_row)
	var apply := Button.new()
	_data_apply_btn = apply
	apply.text = "Commit"
	apply.custom_minimum_size.x = 96
	apply.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	apply.tooltip_text = "Writes the current tree through SaveManager. Live Sync also patches a connected game when enabled."
	apply.pressed.connect(_on_data_apply)
	action_row.add_child(apply)
	_data_discard_btn = Button.new()
	_data_discard_btn.text = "Discard"
	_data_discard_btn.custom_minimum_size.x = 88
	_data_discard_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_data_discard_btn.disabled = true
	_data_discard_btn.pressed.connect(_on_data_discard)
	action_row.add_child(_data_discard_btn)
	_data_pending_label = Label.new()
	_data_pending_label.text = "Pending: 0"
	action_row.add_child(_data_pending_label)
	action_row.add_spacer(false)
	_data_live_sync = CheckBox.new()
	_data_live_sync.text = "Live Sync"
	_data_live_sync.tooltip_text = "When ON and a game is running with the debugger, Commit also patches KV in the running session."
	_data_live_sync.toggled.connect(_on_live_sync_toggled)
	action_row.add_child(_data_live_sync)

	_data_search = LineEdit.new()
	_data_search.placeholder_text = "Search keys…"
	_data_search.text_changed.connect(_on_data_search_changed)
	vb.add_child(_data_search)

	_data_tree = Tree.new()
	_data_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_data_tree.custom_minimum_size = Vector2(0, 240)
	_data_tree.columns = 3
	_data_tree.column_titles_visible = true
	_data_tree.set_column_title(0, "Key")
	_data_tree.set_column_title(1, " ")
	_data_tree.set_column_title(2, "Value")
	_data_tree.set_column_expand(0, true)
	_data_tree.set_column_expand(1, false)
	_data_tree.set_column_expand(2, true)
	_data_tree.set_column_custom_minimum_width(1, 28)
	_data_tree.hide_root = true
	_data_tree.item_edited.connect(_on_data_tree_edited)
	_data_tree.gui_input.connect(_on_data_tree_gui_input)
	vb.add_child(_data_tree)

	_data_color_popup = PopupPanel.new()
	_data_color_popup.name = "DataColorPopup"
	_data_color_popup.exclusive = true
	_data_color_picker_widget = ColorPicker.new()
	_data_color_picker_widget.edit_alpha = true
	_data_color_picker_widget.color_changed.connect(_on_data_color_picker_changed)
	_data_color_popup.add_child(_data_color_picker_widget)
	add_child(_data_color_popup)


func _build_config_tab() -> void:
	var panel := PanelContainer.new()
	panel.name = "Config"
	_tabs.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var l := Label.new()
	l.text = "Mirrors the SaveManager autoload for the editor mirror and when you run the game."
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(1, 1, 1, 0.78)
	vb.add_child(l)

	var sec_files := Label.new()
	sec_files.text = "File & backups"
	sec_files.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92))
	vb.add_child(sec_files)

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

	var sep0 := HSeparator.new()
	vb.add_child(sep0)

	var sec_enc := Label.new()
	sec_enc.text = "Security (Pro)"
	sec_enc.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92))
	vb.add_child(sec_enc)

	var sec_margin := MarginContainer.new()
	sec_margin.add_theme_constant_override("margin_left", 8)
	sec_margin.add_theme_constant_override("margin_right", 8)
	sec_margin.add_theme_constant_override("margin_top", 4)
	sec_margin.add_theme_constant_override("margin_bottom", 4)
	vb.add_child(sec_margin)

	var sec_panel := PanelContainer.new()
	sec_margin.add_child(sec_panel)

	var sec_v := VBoxContainer.new()
	sec_v.add_theme_constant_override("separation", 8)
	sec_panel.add_child(sec_v)

	_cfg_enc = Label.new()
	_cfg_enc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cfg_enc.modulate = Color(1, 1, 1, 0.78)
	_cfg_enc.text = "AES-256 wraps file bytes; HMAC detects tampering. Not a substitute for server authority. Generate keys once per project."
	sec_v.add_child(_cfg_enc)

	_cfg_gen_keys = Button.new()
	_cfg_gen_keys.text = "Generate keys (AES + HMAC)"
	_cfg_gen_keys.custom_minimum_size.y = 32
	_cfg_gen_keys.tooltip_text = "Creates random keys and stores them in Project Settings (savestate_pro/aes_key_hex and savestate_pro/hmac_key_hex), then turns encryption on. Anyone with your project or exported pck can extract keys — this deters casual edits, not determined reverse engineers."
	_cfg_gen_keys.pressed.connect(_on_generate_keys_pressed)
	sec_v.add_child(_cfg_gen_keys)

	_cfg_key_status = Label.new()
	_cfg_key_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cfg_key_status.text = ""
	sec_v.add_child(_cfg_key_status)

	var sep1 := HSeparator.new()
	vb.add_child(sep1)

	_cfg_pro_hint = Label.new()
	_cfg_pro_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cfg_pro_hint.modulate = Color(1, 1, 1, 0.78)
	_cfg_pro_hint.text = ""
	vb.add_child(_cfg_pro_hint)

	_cfg_redetect_btn = Button.new()
	_cfg_redetect_btn.text = "Re-detect SaveManager"
	_cfg_redetect_btn.custom_minimum_size.y = 30
	_cfg_redetect_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_cfg_redetect_btn.tooltip_text = "If you toggle the Pro plugin on/off while the editor is open, refresh which script the dock mirrors."
	_cfg_redetect_btn.pressed.connect(_on_redetect_manager_pressed)
	vb.add_child(_cfg_redetect_btn)


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
	_update_pending_ui()
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
	_cfg_key_status.remove_theme_color_override("font_color")
	if not _pro_enabled:
		_cfg_key_status.text = "Encryption keys: N/A (Lite — enable SaveState Pro to use AES/HMAC)"
		_cfg_key_status.add_theme_color_override("font_color", Color(0.65, 0.65, 0.68))
		return
	var aes_hex := str(ProjectSettings.get_setting("savestate_pro/aes_key_hex", ""))
	var hmac_hex := str(ProjectSettings.get_setting("savestate_pro/hmac_key_hex", ""))
	var has_aes := aes_hex.length() >= 64
	var has_hmac := hmac_hex.length() >= 64
	if has_aes and has_hmac:
		_cfg_key_status.text = "Keys: installed (AES + HMAC)"
		_cfg_key_status.add_theme_color_override("font_color", Color(0.55, 0.82, 0.55))
	else:
		_cfg_key_status.text = "Keys: missing — generate keys before shipping encrypted saves"
		_cfg_key_status.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))


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
	var resume_path := _data_path
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

	# Re-select the file we were editing (e.g. after Data commit) so we don't jump to another list entry.
	var pick_main := -1
	for i in range(mains.size()):
		if mains[i] == resume_path:
			pick_main = i
			break
	var pick_bak := -1
	for j in range(baks.size()):
		if baks[j] == resume_path:
			pick_bak = j
			break
	if pick_main >= 0:
		_list_backup.deselect_all()
		_list_main.select(pick_main)
		_on_explorer_main_selected(pick_main)
	elif pick_bak >= 0:
		_list_main.deselect_all()
		_list_backup.select(pick_bak)
		_on_explorer_backup_selected(pick_bak)
	elif mains.size() > 0:
		_list_backup.deselect_all()
		_list_main.select(0)
		_on_explorer_main_selected(0)


func _is_listed_save_file(fn: String) -> bool:
	# Sidecar JSON for Save Browser color hints — not a SaveState slot payload.
	if fn == ".savestate_editor_hints.json":
		return false
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
	var abs_label := SaveStateUnixDisplay.format_modified_time(mt)
	_info_modified.text = "%s (%s)" % [_format_time_ago(mt), abs_label if not abs_label.is_empty() else "-"]
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


func _on_export_json_explorer() -> void:
	var path := _get_selected_save_path()
	if path.is_empty():
		_toast_show("Select a save file in the list first.", "warn")
		return
	var sm := _get_save_manager()
	if sm == null:
		_toast_show("SaveManager not available.", "warn")
		return
	var out_path := path.get_base_dir().path_join(path.get_file().get_basename() + "_savestate_export.json")
	var err: int = sm.export_save_file_to_json(path, out_path)
	if err != OK:
		_toast_show("Export failed: %s" % error_string(err), "warn")
		_log("export json failed: %s" % error_string(err))
		return
	_log("exported JSON: %s" % out_path)
	_toast_show("Wrote %s" % out_path.get_file(), "ok")
	var abs_dir := ProjectSettings.globalize_path(out_path.get_base_dir())
	if DirAccess.dir_exists_absolute(abs_dir):
		OS.shell_open(abs_dir)


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
	_reload_data_editor_hints()
	_data_status.text = "Editing: %s (%d keys)" % [_data_path.get_file(), _data_flat.size()]
	_refill_data_tree()
	call_deferred("_refresh_data_color_picker_from_selection")


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


func _data_set_row_value_visual(it: TreeItem, key: String, v: Variant) -> void:
	var val_str := _value_to_edit_string(v)
	it.set_text(DATA_COL_VALUE, val_str)
	it.clear_custom_bg_color(DATA_COL_VALUE)
	it.set_icon(DATA_COL_SWATCH, null)
	it.set_tooltip_text(DATA_COL_SWATCH, "")
	if _data_row_should_show_color_ui(key, v) and _dock_is_color_like(v):
		var cc := _dock_variant_to_color(v)
		it.set_icon(DATA_COL_SWATCH, _dock_swatch_texture(cc))
		it.set_custom_bg_color(DATA_COL_VALUE, Color(cc.r, cc.g, cc.b, 0.22))
		it.set_tooltip_text(DATA_COL_SWATCH, "Click to edit color (Pro)")


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
		var ks := str(k)
		it.set_text(DATA_COL_KEY, ks)
		_data_set_row_value_visual(it, ks, _data_flat[k])
		it.set_editable(DATA_COL_KEY, false)
		it.set_editable(DATA_COL_SWATCH, false)
		it.set_editable(DATA_COL_VALUE, allow_edit)


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
	if _data_tree.get_edited_column() != DATA_COL_VALUE:
		return
	if not _pro_enabled:
		_toast_show("Editing is a Pro feature (Lite is read-only).", "warn")
		var k0 := str(it.get_text(DATA_COL_KEY))
		if _data_flat.has(k0):
			_data_set_row_value_visual(it, k0, _data_flat[k0])
		return
	var k := str(it.get_text(DATA_COL_KEY))
	var vstr := str(it.get_text(DATA_COL_VALUE))
	var v := _parse_value_string(vstr)
	_data_flat[k] = v
	var had_orig := _data_original_flat.has(k)
	var orig := _data_original_flat.get(k, null)
	if (not had_orig and v != null) or (had_orig and _variant_neq(orig, v)):
		_data_pending[k] = v
	else:
		_data_pending.erase(k)
	_update_pending_ui()
	call_deferred("_refresh_data_color_picker_from_selection")


func _reload_data_editor_hints() -> void:
	_data_editor_hints.clear()
	var sm := _get_save_manager()
	if sm != null and sm.has_method("get_editor_hints_copy"):
		_data_editor_hints = sm.get_editor_hints_copy()
	else:
		_try_load_hints_from_save_root(_get_save_root())


func _try_load_hints_from_save_root(root: String) -> void:
	if root.is_empty():
		return
	var p := root.path_join(".savestate_editor_hints.json")
	if not FileAccess.file_exists(p):
		return
	var txt := FileAccess.get_file_as_string(p)
	var j: Variant = JSON.parse_string(txt)
	if typeof(j) != TYPE_DICTIONARY:
		return
	for k in j:
		_data_editor_hints[str(k)] = int(j[k])


func _on_data_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var pos := _data_tree.get_local_mouse_position()
			var item := _data_tree.get_item_at_position(pos)
			if item != null:
				var col := _data_tree.get_column_at_position(pos)
				if col == DATA_COL_SWATCH:
					_open_color_picker_from_swatch(item)
			call_deferred("_refresh_data_color_picker_from_selection")


func _data_row_should_show_color_ui(key: String, v: Variant) -> bool:
	if _data_editor_hints.has(key):
		var h := int(_data_editor_hints[key])
		if h == 1:
			return _dock_is_color_like(v)
		return false
	return _dock_is_color_like(v)


func _refresh_data_color_picker_from_selection() -> void:
	if _data_color_popup == null:
		return
	var it := _data_tree.get_selected()
	if it == null:
		_data_color_bound_key = ""
		return
	var k := str(it.get_text(DATA_COL_KEY))
	var v: Variant = _data_flat.get(k, null)
	if not _data_row_should_show_color_ui(k, v) or not _dock_is_color_like(v):
		_data_color_bound_key = ""
		return
	_data_color_bound_key = k


func _open_color_picker_from_swatch(item: TreeItem) -> void:
	var k := str(item.get_text(DATA_COL_KEY))
	var v: Variant = _data_flat.get(k, null)
	if not _data_row_should_show_color_ui(k, v) or not _dock_is_color_like(v):
		return
	if not _pro_enabled:
		_toast_show("Editing is a Pro feature (Lite is read-only).", "warn")
		return
	_data_color_bound_key = k
	var col := _dock_variant_to_color(v)
	_data_color_changing = true
	if _data_color_picker_widget != null:
		_data_color_picker_widget.color = col
	_data_color_changing = false
	if _data_color_popup != null:
		_data_color_popup.popup_centered(Vector2(380, 460))


func _on_data_color_picker_changed(new_color: Color) -> void:
	if _data_color_changing or _data_color_bound_key.is_empty():
		return
	if not _pro_enabled:
		return
	var k := _data_color_bound_key
	var prev: Variant = _data_flat.get(k, Color.WHITE)
	var nv: Variant = _dock_color_to_storage(new_color, prev)
	_data_flat[k] = nv
	var had_orig := _data_original_flat.has(k)
	var orig := _data_original_flat.get(k, null)
	if (not had_orig and nv != null) or (had_orig and _variant_neq(orig, nv)):
		_data_pending[k] = nv
	else:
		_data_pending.erase(k)
	_update_pending_ui()
	var it := _data_tree.get_selected()
	if it != null and str(it.get_text(DATA_COL_KEY)) == k:
		_data_set_row_value_visual(it, k, nv)


func _dock_try_parse_paren_color_string(s: String) -> Variant:
	var t := s.strip_edges()
	if not (t.begins_with("(") and t.ends_with(")")):
		return null
	var inner := t.substr(1, t.length() - 2).strip_edges()
	var parts := inner.split(",")
	if parts.size() < 3:
		return null
	var r := float(str(parts[0]).strip_edges())
	var g := float(str(parts[1]).strip_edges())
	var b := float(str(parts[2]).strip_edges())
	var a := float(str(parts[3]).strip_edges()) if parts.size() > 3 else 1.0
	if is_nan(r) or is_nan(g) or is_nan(b) or is_nan(a):
		return null
	return Color(r, g, b, a)


func _dock_is_color_like(v: Variant) -> bool:
	var t := typeof(v)
	if t == TYPE_COLOR:
		return true
	if t == TYPE_STRING:
		return _dock_try_parse_paren_color_string(str(v)) != null
	if v is Dictionary:
		var d: Dictionary = v
		return d.has("r") and d.has("g") and d.has("b")
	if v is Array:
		return (v as Array).size() >= 3 and (v as Array).size() <= 4
	return false


func _dock_variant_to_color(v: Variant) -> Color:
	if typeof(v) == TYPE_COLOR:
		return v
	if typeof(v) == TYPE_STRING:
		var pc: Variant = _dock_try_parse_paren_color_string(str(v))
		return pc if pc is Color else Color.WHITE
	if v is Dictionary:
		var d: Dictionary = v
		var r := float(d.get("r", d.get("red", 0.0)))
		var g := float(d.get("g", d.get("green", 0.0)))
		var b := float(d.get("b", d.get("blue", 0.0)))
		var a := float(d.get("a", d.get("alpha", 1.0)))
		if r > 1.0 or g > 1.0 or b > 1.0:
			r /= 255.0
			g /= 255.0
			b /= 255.0
			if a > 1.0:
				a /= 255.0
		return Color(r, g, b, a)
	if v is Array:
		var arr: Array = v
		if arr.size() >= 3:
			return Color(
				float(arr[0]),
				float(arr[1]),
				float(arr[2]),
				float(arr[3]) if arr.size() > 3 else 1.0
			)
	return Color.WHITE


func _dock_color_to_storage(c: Color, previous: Variant) -> Variant:
	if typeof(previous) == TYPE_COLOR:
		return c
	if typeof(previous) == TYPE_STRING:
		return str(c)
	if previous is Dictionary:
		return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
	if previous is Array:
		return [c.r, c.g, c.b, c.a]
	return c


func _update_pending_ui() -> void:
	if _data_pending_label != null:
		_data_pending_label.text = "Pending: %d" % _data_pending.size()
	if _data_discard_btn != null:
		_data_discard_btn.disabled = _data_pending.is_empty() or not _pro_enabled
	if _data_apply_btn != null:
		_data_apply_btn.disabled = _data_pending.is_empty() or not _pro_enabled


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


## Avoid `orig != v` when types differ (e.g. [Color] vs [String] from the tree) — Godot errors on mixed-type inequality.
func _variant_neq(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return true
	return a != b


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


func _on_backup_selected_now() -> void:
	var path := _get_selected_save_path()
	if path.is_empty():
		_toast_show("Select a main save first.", "warn")
		return
	if path.ends_with(".bak"):
		_toast_show("Use a row under Main saves — not a .bak file.", "warn")
		return
	var sm := _get_save_manager()
	if sm == null:
		_toast_show("SaveManager not available.", "warn")
		return
	var err: Error = sm.create_backup_copy_for_file(path) as Error
	if err != OK:
		_toast_show("Backup failed: %s" % error_string(err), "err")
		_log("backup selected failed: %s path=%s" % [error_string(err), path])
		return
	_log("backup selected OK path=%s" % path)
	_toast_show("Wrote %s.bak" % path.get_file(), "ok")
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
