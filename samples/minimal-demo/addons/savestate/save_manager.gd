class_name SaveManagerBase
extends Node
## Base implementation for the [code]SaveManager[/code] autoload: slot registry, synchronous save/load, atomic writes via [AtomicWriter]. Pro subclasses add async + crypto.
## Note: The autoload must be named [code]SaveManager[/code]; the global class is [code]SaveManagerBase[/code] to avoid Godot’s “collision with global script class name” rule.

signal save_started(slot_id: StringName)
signal save_completed(slot_id: StringName)
signal save_failed(slot_id: StringName, error: int)
signal load_started(slot_id: StringName)
signal load_completed(slot_id: StringName, data: Dictionary)
signal load_failed(slot_id: StringName, error: int)
## Emitted before [method persist_including_saveables] / Pro async persist so [Saveable] nodes can react (optional).
signal save_requested()
## Emitted when you call [method load_from_slot_and_apply_saveables] after data is read.
signal load_requested()
## Fires when a loaded file’s embedded [code]schema_version[/code] is older than [method get_current_schema_version]. Use this in Lite to run custom data fixes without Pro’s migration tools.
signal migration_required(old_schema_version: int, new_schema_version: int)

const FLAG_JSON: int = 1
const FORMAT_VERSION: int = 1

const SETTING_SCHEMA_VERSION := "savestate/current_version"
## Reserved slot for [method set_value] / [method get_value] / [method persist]. Avoid using [code]slot_0[/code] for unrelated data, or call [method clear_kv_cache] first.
const KV_SLOT_ID: StringName = &"slot_0"

## Root directory for save files ([code]user://...[/code]).
@export var save_root: String = "user://savestate"
## When [code]true[/code], payload is JSON UTF-8; otherwise [method @GlobalScope.var_to_bytes] on the envelope [Dictionary].
@export var use_json: bool = false
## When [code]true[/code], existing save files are renamed to [code].bak[/code] before a new commit (default ON; same as Pro).
@export var backup_on_commit: bool = true

var _slots: Dictionary = {} # StringName -> SaveSlot
var _default_state: Dictionary = {}
var _kv_data: Dictionary = {}
var _kv_hydrated: bool = false
var _debug_capture_registered: bool = false


func _ready() -> void:
	_ensure_save_root()
	if not ProjectSettings.has_setting(SETTING_SCHEMA_VERSION):
		ProjectSettings.set_setting(SETTING_SCHEMA_VERSION, 1)
	_register_reserved_kv_slot()
	_register_live_edit_debugger_capture()


func _register_live_edit_debugger_capture() -> void:
	# Optional “time traveler” support: allow editor debugger to push patches into a running game.
	# Safe no-op when not running under debugger.
	if not EngineDebugger.is_active():
		return
	if _debug_capture_registered:
		return
	var cap: StringName = &"savestate_pro"
	EngineDebugger.register_message_capture(cap, Callable(self, "_on_debugger_message"))
	_debug_capture_registered = true


func _on_debugger_message(message: StringName, data: Array) -> void:
	var msg := str(message)
	if not msg.begins_with("savestate_pro:"):
		return
	var parts := msg.split(":", false, 2)
	var cmd := parts[1] if parts.size() > 1 else ""
	if cmd == "apply_kv_patch":
		var patch: Dictionary = {}
		if data.size() >= 1 and data[0] is Dictionary:
			patch = data[0] as Dictionary
		_apply_kv_patch(patch)


func _apply_kv_patch(patch: Dictionary) -> void:
	if patch.is_empty():
		return
	_hydrate_kv_if_needed()
	for k in patch:
		_kv_data[k] = patch[k]
	_kv_hydrated = true
	load_requested.emit()
	# If saveables bundle is included, apply it too.
	if patch.has("__saveables") and patch["__saveables"] is Dictionary:
		apply_saveables_from_bundle(patch["__saveables"] as Dictionary)


func _register_reserved_kv_slot() -> void:
	if _slots.has(KV_SLOT_ID):
		return
	var s := SaveSlot.new()
	s.slot_id = KV_SLOT_ID
	s.file_base_name = "slot_0"
	s.display_name = "KV Store"
	register_slot(s)


## One-line style storage: [code]set_value[/code] / [code]get_value[/code], then [method persist] to flush [code]slot_0[/code] to disk.
func set_value(key: StringName, value: Variant) -> void:
	_hydrate_kv_if_needed()
	_kv_data[key] = value


func get_value(key: StringName, default: Variant = null) -> Variant:
	_hydrate_kv_if_needed()
	return _kv_data.get(key, default)


## Writes the KV dictionary to the reserved [member KV_SLOT_ID] file (sync, atomic).
func persist() -> Error:
	_hydrate_kv_if_needed()
	return save_to_slot_sync(KV_SLOT_ID, _kv_data)


## Clears in-memory KV and will reload from disk on next access.
func clear_kv_cache() -> void:
	_kv_data.clear()
	_kv_hydrated = false


## Replace KV data entirely (e.g. after loading a custom slot). Does not write disk until [method persist].
func replace_kv_data(data: Dictionary) -> void:
	_kv_data = data.duplicate(true)
	_kv_hydrated = true


## If [param main_save_path] is [code]user://.../slot_0.bin[/code], a sibling [code]slot_0.bin.bak[/code] replaces it. Used by the editor Restore button.
func gather_saveable_snapshots() -> Dictionary:
	var out := {}
	var tree := get_tree()
	if tree == null:
		return out
	for n in tree.get_nodes_in_group("savestate_saveable"):
		if not (n is Node):
			continue
		var node: Node = n
		if not node.has_method("get_storage_key") or not node.has_method("collect_snapshot"):
			continue
		var sk: Variant = node.call("get_storage_key")
		out[StringName(str(sk))] = node.call("collect_snapshot")
	return out


func persist_including_saveables() -> Error:
	save_requested.emit()
	_hydrate_kv_if_needed()
	var merged := _kv_data.duplicate(true)
	merged["__saveables"] = gather_saveable_snapshots()
	return save_to_slot_sync(KV_SLOT_ID, merged)


## Loads slot data, emits [signal load_requested], applies [Saveable] snapshots under [code]__saveables[/code].
func load_from_slot_and_apply_saveables(slot_id: StringName) -> Dictionary:
	var inner := load_from_slot_sync(slot_id)
	load_requested.emit()
	var b: Variant = inner.get("__saveables", {})
	if typeof(b) == TYPE_DICTIONARY:
		apply_saveables_from_bundle(b as Dictionary)
	return inner


func apply_saveables_from_bundle(bundle: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("savestate_saveable"):
		if not (n is Node):
			continue
		var node: Node = n
		if not node.has_method("get_storage_key") or not node.has_method("apply_snapshot"):
			continue
		var sk: Variant = node.call("get_storage_key")
		var d: Variant = bundle.get(sk, null)
		if d == null:
			d = bundle.get(str(sk), null)
		if d is Dictionary:
			node.call("apply_snapshot", d)


## Ensures a [SaveSlot] exists for [param file_base] (e.g. [code]slot_0[/code] for [code]slot_0.bin[/code]) and writes [param inner] payload.
func write_inner_data_to_disk(path: String, inner: Dictionary) -> Error:
	var fn := path.get_file()
	if fn.ends_with(".bak"):
		fn = fn.trim_suffix(".bak")
	var base := fn.get_basename()
	if base.is_empty():
		return ERR_INVALID_PARAMETER
	var slot_id := StringName(base)
	ensure_slot_for_file_base(slot_id, base)
	return save_to_slot_sync(slot_id, inner)


func ensure_slot_for_file_base(slot_id: StringName, file_base: String) -> void:
	if _slots.has(slot_id):
		return
	var s := SaveSlot.new()
	s.slot_id = slot_id
	s.file_base_name = file_base
	s.display_name = str(file_base)
	register_slot(s)


func restore_from_backup_file(main_save_path: String) -> Error:
	var bak_path := main_save_path + ".bak"
	if not FileAccess.file_exists(bak_path):
		return ERR_FILE_NOT_FOUND
	if FileAccess.file_exists(main_save_path):
		var rm := DirAccess.remove_absolute(main_save_path)
		if rm != OK:
			return rm
	return DirAccess.rename_absolute(bak_path, main_save_path)


func _hydrate_kv_if_needed() -> void:
	if _kv_hydrated:
		return
	_register_reserved_kv_slot()
	_kv_data = _read_slot_inner_silent(KV_SLOT_ID)
	_kv_hydrated = true


func _read_slot_inner_silent(slot_id: StringName) -> Dictionary:
	var slot: SaveSlot = _slots.get(slot_id) as SaveSlot
	if slot == null:
		return {}
	var path := slot.get_file_path(save_root, use_json)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw := file.get_buffer(file.get_length())
	file.close()
	var processed := _post_read_transform(raw)
	var pr := parse_save_file_buffer(processed)
	if pr.get("ok", false):
		return (pr["data"] as Dictionary).duplicate(true)
	return {}


func _ensure_save_root() -> void:
	var absolute := ProjectSettings.globalize_path(save_root)
	DirAccess.make_dir_recursive_absolute(absolute)


func register_slot(slot: SaveSlot) -> void:
	_slots[slot.slot_id] = slot


func unregister_slot(slot_id: StringName) -> void:
	_slots.erase(slot_id)


func get_slot(slot_id: StringName) -> SaveSlot:
	return _slots.get(slot_id) as SaveSlot


func set_default_state_for_migration(defaults: Dictionary) -> void:
	_default_state = defaults.duplicate(true)


func get_current_schema_version() -> int:
	if ProjectSettings.has_setting(SETTING_SCHEMA_VERSION):
		return int(ProjectSettings.get_setting(SETTING_SCHEMA_VERSION))
	return 1


## Synchronous save (Lite). Override [method _pre_write_transform] in Pro for encryption.
func save_to_slot_sync(slot_id: StringName, data: Dictionary) -> Error:
	save_started.emit(slot_id)
	var slot: SaveSlot = _slots.get(slot_id) as SaveSlot
	if slot == null:
		save_failed.emit(slot_id, ERR_DOES_NOT_EXIST)
		return ERR_DOES_NOT_EXIST

	var path := slot.get_file_path(save_root, use_json)
	var payload := _serialize_envelope(data)
	var flags := FLAG_JSON if use_json else 0
	var file_bytes := _compose_file_bytes(FORMAT_VERSION, get_current_schema_version(), flags, payload)
	var final_bytes := _pre_write_transform(file_bytes)
	var err := AtomicWriter.write_atomic(path, final_bytes, backup_on_commit)
	if err == OK:
		slot.last_modified_unix = int(Time.get_unix_time_from_system())
		slot.file_schema_version = get_current_schema_version()
		if slot_id == KV_SLOT_ID:
			_kv_data = data.duplicate(true)
			_kv_hydrated = true
		save_completed.emit(slot_id)
	else:
		save_failed.emit(slot_id, err)
	return err


## Synchronous load (Lite).
func load_from_slot_sync(slot_id: StringName) -> Dictionary:
	load_started.emit(slot_id)
	var slot: SaveSlot = _slots.get(slot_id) as SaveSlot
	if slot == null:
		load_failed.emit(slot_id, ERR_DOES_NOT_EXIST)
		return {}

	var path := slot.get_file_path(save_root, use_json)
	if not FileAccess.file_exists(path):
		load_failed.emit(slot_id, ERR_FILE_NOT_FOUND)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var e := FileAccess.get_open_error()
		load_failed.emit(slot_id, e)
		return {}
	var raw := file.get_buffer(file.get_length())
	file.close()

	var processed := _post_read_transform(raw)
	var pr := parse_save_file_buffer(processed)
	if not pr.get("ok", false):
		load_failed.emit(slot_id, int(pr.get("error", ERR_FILE_CORRUPT)))
		return {}

	var inner: Dictionary = pr["data"] as Dictionary
	var file_schema := int(pr.get("schema_version", 0))
	slot.file_schema_version = file_schema
	var current_schema := get_current_schema_version()
	if file_schema < current_schema:
		migration_required.emit(file_schema, current_schema)
	if slot_id == KV_SLOT_ID:
		_kv_data = inner.duplicate(true)
		_kv_hydrated = true
	load_completed.emit(slot_id, inner)
	return inner


## Parses decrypted/unwrapped file bytes (SSP1 inner format). Used by async load and tools.
func parse_save_file_buffer(processed: PackedByteArray) -> Dictionary:
	if processed.is_empty():
		return {"ok": false, "error": ERR_FILE_CORRUPT, "data": {}}

	var parsed := _parse_file_bytes(processed)
	if not parsed.has("schema_version"):
		return {"ok": false, "error": ERR_FILE_CORRUPT, "data": {}}

	var schema := int(parsed.get("schema_version", 0))
	var inner: Dictionary = parsed.get("data", {}) as Dictionary
	if typeof(inner) != TYPE_DICTIONARY:
		inner = {}

	if schema < get_current_schema_version() and not _default_state.is_empty():
		inner = SaveMigrator.deep_merge(inner, _default_state)

	return {"ok": true, "error": OK, "data": inner, "schema_version": schema}


## Editor / tools: read a save file through the same decrypt + parse pipeline as runtime load.
func debug_inspect_save_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": ERR_FILE_NOT_FOUND, "hex_preview": "", "json_preview": "", "thumb_path": "", "inner_dict": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": FileAccess.get_open_error(), "hex_preview": "", "json_preview": "", "thumb_path": "", "inner_dict": {}}
	var raw := file.get_buffer(file.get_length())
	file.close()
	var processed := _post_read_transform(raw)
	var pr := parse_save_file_buffer(processed)
	var json_preview := ""
	if pr.get("ok", false):
		json_preview = JSON.stringify(pr["data"] as Dictionary)
	var hex_preview := raw.hex_encode()
	const MAX_HEX := 4096
	if hex_preview.length() > MAX_HEX:
		hex_preview = hex_preview.substr(0, MAX_HEX) + "\n… (truncated)"
	var thumb_full := path.get_base_dir().path_join(path.get_file().get_basename() + ".jpg")
	if not FileAccess.file_exists(thumb_full):
		thumb_full = ""

	var inner_dict := {}
	if pr.get("ok", false):
		inner_dict = (pr["data"] as Dictionary).duplicate(true)

	var health := debug_health_for_path(path)
	return {
		"ok": pr.get("ok", false),
		"error": pr.get("error", OK),
		"hex_preview": hex_preview,
		"json_preview": json_preview,
		"raw_size": raw.size(),
		"thumb_path": thumb_full,
		"inner_dict": inner_dict,
		"health": health,
	}


## Virtual: Pro overrides to encrypt/sign whole file bytes before atomic write.
func _pre_write_transform(file_bytes: PackedByteArray) -> PackedByteArray:
	return file_bytes


## Virtual: Pro overrides to verify/decrypt after read.
func _post_read_transform(raw: PackedByteArray) -> PackedByteArray:
	return raw


## Virtual: Pro overrides to provide AES/HMAC keys for editor verification.
## Return: {"aes": PackedByteArray, "hmac": PackedByteArray} or empty arrays if unavailable.
func _get_debug_crypto_keys() -> Dictionary:
	return {"aes": PackedByteArray(), "hmac": PackedByteArray()}


## Editor / tools: quick health summary without requiring a full decode in the UI.
## This returns enough information to show badges: encrypted/verified/warning, schema/version mismatches, saveables presence, and counts.
func debug_health_for_path(path: String) -> Dictionary:
	var out := {
		"exists": false,
		"ok": false,
		"error": OK,
		"raw_size": 0,
		"modified_unix": 0,
		"format_version": 0,
		"flags": 0,
		"schema_version": 0,
		"current_schema_version": get_current_schema_version(),
		"needs_migration": false,
		"encrypted_outer": false,
		"keys_present": false,
		"verified": null, # bool|null (unknown)
		"verify_error": OK,
		"key_count": 0,
		"has_saveables": false,
		"saveables_count": 0,
	}

	if not FileAccess.file_exists(path):
		out["error"] = ERR_FILE_NOT_FOUND
		return out
	out["exists"] = true
	out["modified_unix"] = int(FileAccess.get_modified_time(path))

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		out["error"] = FileAccess.get_open_error()
		return out
	var raw := file.get_buffer(file.get_length())
	file.close()
	out["raw_size"] = raw.size()

	var h := SaveFormat.parse_header(raw)
	if int(h.get("error", OK)) != OK:
		out["error"] = int(h.get("error", ERR_FILE_CORRUPT))
		return out

	out["format_version"] = int(h.get("format_version", 0))
	out["flags"] = int(h.get("flags", 0))
	out["schema_version"] = int(h.get("schema_version", 0))
	out["encrypted_outer"] = int(out["format_version"]) == int(SaveSecurity.OUTER_FORMAT_VERSION)

	var processed := raw
	if bool(out["encrypted_outer"]):
		var keys := _get_debug_crypto_keys()
		var aes: PackedByteArray = keys.get("aes", PackedByteArray()) as PackedByteArray
		var hmac: PackedByteArray = keys.get("hmac", PackedByteArray()) as PackedByteArray
		out["keys_present"] = aes.size() == int(SaveSecurity.AES_KEY_SIZE) and not hmac.is_empty()
		if bool(out["keys_present"]):
			var opened := SaveSecurity.open_outer_save_file(raw, aes, hmac)
			var verr := int(opened.get("error", ERR_FILE_CORRUPT))
			out["verify_error"] = verr
			out["verified"] = verr == OK
			if verr == OK:
				processed = opened.get("inner", PackedByteArray()) as PackedByteArray
		else:
			out["verified"] = null

	var pr := parse_save_file_buffer(processed)
	out["ok"] = bool(pr.get("ok", false))
	if not bool(out["ok"]):
		out["error"] = int(pr.get("error", ERR_FILE_CORRUPT))
		return out

	var inner: Dictionary = pr.get("data", {}) as Dictionary
	out["schema_version"] = int(pr.get("schema_version", out["schema_version"]))
	out["needs_migration"] = int(out["schema_version"]) < int(out["current_schema_version"])
	out["key_count"] = inner.size()
	if inner.has("__saveables") and inner["__saveables"] is Dictionary:
		out["has_saveables"] = true
		out["saveables_count"] = (inner["__saveables"] as Dictionary).size()
	return out


func _serialize_envelope(data: Dictionary) -> PackedByteArray:
	var envelope := {"schema_version": get_current_schema_version(), "data": data}
	if use_json:
		return JSON.stringify(envelope).to_utf8_buffer()
	return var_to_bytes(envelope)


func _compose_file_bytes(
		format_ver: int,
		schema_ver: int,
		flags: int,
		payload: PackedByteArray
	) -> PackedByteArray:
	var header := SaveFormat.build_header(format_ver, schema_ver, flags, payload.size())
	var out := header
	out.append_array(payload)
	return out


func _parse_file_bytes(file_bytes: PackedByteArray) -> Dictionary:
	var h := SaveFormat.parse_header(file_bytes)
	if int(h.get("error", OK)) != OK:
		return {}
	var payload_len: int = int(h["payload_len"])
	if file_bytes.size() < SaveFormat.HEADER_SIZE + payload_len:
		return {}
	var payload := file_bytes.slice(SaveFormat.HEADER_SIZE, SaveFormat.HEADER_SIZE + payload_len)
	var flags: int = int(h["flags"])
	return _parse_payload(payload, flags)


func _parse_payload(payload: PackedByteArray, flags: int) -> Dictionary:
	if flags & FLAG_JSON:
		var txt := payload.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(txt)
		if typeof(parsed) != TYPE_DICTIONARY:
			return {}
		return parsed as Dictionary
	var v: Variant = bytes_to_var(payload)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return v as Dictionary
