class_name SaveManagerBase
extends Node
## Base implementation for the [code]SaveManager[/code] autoload: slot registry, synchronous save/load, atomic writes via [AtomicWriter]. Pro subclasses add async + crypto.
## Note: The autoload must be named [code]SaveManager[/code]; the global class is [code]SaveManagerBase[/code] to avoid Godot’s “collision with global script class name” rule.

signal save_started(slot_id: StringName)
signal operation_finished(result: SaveStateResult)
signal save_completed(slot_id: StringName)
signal save_failed(slot_id: StringName, error: int)
signal load_started(slot_id: StringName)
signal load_completed(slot_id: StringName, data: Dictionary)
signal load_failed(slot_id: StringName, error: int)
## Emitted once per explicit load, after acceptance or rejection. Legacy signals remain available.
signal load_finished(result: SaveStateLoadResult)
## Emitted before [method persist_including_saveables] / Pro async persist so [Saveable] nodes can react (optional).
signal autosave_paused(error: int)
signal debug_reply(message: String, data: Array)
signal save_requested()
## Emitted when you call [method load_from_slot_and_apply_saveables] after data is read.
signal load_requested()
## Post-acceptance notification for an older file. Put required transforms in [method set_schema_migrations].
signal migration_required(old_schema_version: int, new_schema_version: int)

const FLAG_JSON: int = 1
const FORMAT_VERSION: int = 1
const _EncryptedSaveReader := preload("res://addons/savestate/encrypted_save_reader.gd")
## Pass to [method register_key] as the 4th argument: auto-pick editor hint from [param expected_type], or force none / color for Save Browser.
const KV_EDITOR_HINT_AUTO := -1
const KV_EDITOR_HINT_NONE := 0
const KV_EDITOR_HINT_COLOR := 1

const SETTING_SCHEMA_VERSION := "savestate/current_version"
## Reserved slot for [method set_value] / [method get_value] / [method persist]. Avoid using [code]slot_0[/code] for unrelated data, or call [method clear_kv_cache] first.
const KV_SLOT_ID: StringName = &"slot_0"

## Root directory for save files ([code]user://...[/code]).
@export var save_root: String = str(ProjectSettings.get_setting("savestate/save_root", "user://savestate"))
## When [code]true[/code], payload is JSON UTF-8; otherwise [method @GlobalScope.var_to_bytes] on the envelope [Dictionary].
@export var use_json: bool = false
## When [code]true[/code], existing save files are renamed to [code].bak[/code] before a new commit (default ON; same as Pro).
@export var backup_on_commit: bool = true
## Number of ordinary retained generations; protected and unreadable files are kept separately.
@export var generation_retention: int = 5

var _slots: Dictionary = {} # StringName -> SaveSlot
var _default_state: Dictionary = {}
var _kv_data: Dictionary = {}
var _kv_hydrated: bool = false
var _last_load_result: SaveStateLoadResult
var _kv_load_failure: SaveStateLoadResult
var _load_active: bool = false
var _load_lease: String = ""
var _playthrough_session: SaveStatePlaythroughSession
var _runtime_revision: int = 0
var _migration_revision: int = 0
var _debug_capture_registered: bool = false
## v1.2: [StringName -> int] expected [method @GlobalScope.typeof] for [method set_value] validation.
var _kv_types: Dictionary = {}
## v1.2: defaults used when a registered key is missing from loaded data / [method get_value].
var _kv_registered_defaults: Dictionary = {}
## v1.2: ordered callables; entry at index [code]i[/code] runs when upgrading from schema [code]i + 1[/code] to [code]i + 2[/code].
var _schema_migrations: Array = []
var _dirty_pending: bool = false
var _dirty_timer: Timer
var _dirty_revision: int = 0
var _dirty_first_usec: int = 0
var _dirty_last_usec: int = 0
var _dirty_retries: int = 0
var _dirty_inflight: bool = false
var _auto_request: bool = false
var _write_active: bool = false
var _closing: bool = false
var _cache_epoch: int = 0
@export var auto_save_max_interval_sec: float = 30.0
@export var auto_save_retry_limit: int = 3
@export var auto_save_retry_base_sec: float = 0.5
## Flat key path (e.g. [code]player.tint[/code]) → [constant KV_EDITOR_HINT_COLOR]. Persisted next to saves as [code].savestate_editor_hints.json[/code].
var _editor_flat_hints: Dictionary = {}

## After [method mark_dirty], wait this many seconds of silence before [method _execute_debounced_persist] (default sync persist; Pro overrides for async).
@export var auto_save_debounce_sec: float = 2.0
## When true, debounced flush calls [method persist_including_saveables] / Pro async equivalent instead of KV-only [method persist].
@export var dirty_persist_includes_saveables: bool = false


func _ready() -> void:
	_ensure_save_root()
	if not ProjectSettings.has_setting(SETTING_SCHEMA_VERSION):
		ProjectSettings.set_setting(SETTING_SCHEMA_VERSION, 1)
	var setup_path := str(ProjectSettings.get_setting("savestate/schema_setup_script", ""))
	if setup_path.begins_with("res://") and setup_path.ends_with(".gd") and ResourceLoader.exists(setup_path):
		var setup_script: Script = load(setup_path)
		var setup: Object = setup_script.new()
		if setup.has_method("configure"): setup.configure(self)
		if setup is Node: setup.free()
	_register_reserved_kv_slot()
	_register_live_edit_debugger_capture()
	_setup_dirty_timer()
	_load_editor_hints_from_disk()


func _register_live_edit_debugger_capture() -> void:
	# Register acknowledged live edits only for a connected debug build.
	# Safe no-op when not running under debugger.
	if not OS.is_debug_build() or not EngineDebugger.is_active() or Engine.is_editor_hint():
		return
	if _debug_capture_registered:
		return
	var cap: StringName = &"savestate_pro"
	EngineDebugger.register_message_capture(cap, Callable(self, "_on_debugger_message"))
	_debug_capture_registered = true


func _on_debugger_message(message: StringName, data: Array) -> bool:
	if not OS.is_debug_build():
		return false
	if message == &"inspect_v2":
		if data.size() == 1 and data[0] is int: _send_debug_reply("state_v2", [data[0], _debug_state_v2()])
		return true
	if message == &"patch_v2":
		if data.size() == 1 and data[0] is Dictionary:
			var request: Dictionary = data[0]
			_send_debug_reply("result_v2", [int(request.get("id", -1)), _apply_debug_v2(request), _runtime_revision, "memory"])
		return true
	if message == &"save_v2":
		if data.size() == 1 and data[0] is Dictionary: call_deferred("_debug_save_v2", data[0])
		return true
	if message == &"inspect":
		if data.size() == 1 and data[0] is int:
			_send_debug_reply("state", [data[0], _debug_state()])
		return true
	if message == &"apply_patch":
		if data.size() == 1 and data[0] is Dictionary:
			var request: Dictionary = data[0]
			var error := _apply_debug_request(request)
			_send_debug_reply("patch_result", [int(request.get("id", -1)), error, _runtime_revision])
		return true
	# Older unversioned messages are recognized but never applied without conflict checks.
	return message == &"apply_kv_patch"


func _debug_state() -> Dictionary:
	_register_reserved_kv_slot()
	var hydrated := _hydrate_kv_if_needed()
	return {"protocol": 1, "revision": _runtime_revision, "path": _slots[KV_SLOT_ID].get_file_path(save_root, use_json),
		"busy": _load_active or _has_pending_writes(), "error": OK if hydrated else _kv_load_failure.error}


func _apply_debug_request(request: Dictionary) -> Error:
	if _load_active or _has_pending_writes() or _closing:
		return ERR_BUSY
	if request.get("protocol") != 1 or not (request.get("operations") is Array):
		return ERR_INVALID_DATA
	if not _hydrate_kv_if_needed():
		return _kv_load_failure.error
	var state := _debug_state()
	if request.get("path") != state["path"] or request.get("revision") != _runtime_revision:
		return ERR_BUSY
	for operation in request["operations"]:
		if not (operation is Dictionary) or not operation.has("before"):
			return ERR_INVALID_DATA
		# Applying scene callbacks is outside this maintenance patch's live-edit contract.
		if operation.get("path") is Array and not operation["path"].is_empty() 				and operation["path"][0] is Dictionary and str(operation["path"][0].get("key", "")) == "__saveables":
			return ERR_UNAVAILABLE
	var result := SaveStateData.patch(_kv_data, request["operations"])
	if int(result["error"]) != OK:
		return int(result["error"]) as Error
	if not _validate_loaded_data(result["data"]).is_empty():
		return ERR_INVALID_DATA
	_kv_data = result["data"]
	_runtime_revision += 1
	_touch_pending_dirty()
	return OK


func _debug_state_v2() -> Dictionary:
	var result := {"protocol": 2, "project": ProjectSettings.globalize_path("res://"), "session": get_instance_id(),
		"root": ProjectSettings.globalize_path(save_root), "revision": _runtime_revision, "context": get_active_context(),
		"busy": _load_active or _has_pending_writes(), "error": OK, "data": {}}
	if not _session_enabled(): result.error = ERR_UNCONFIGURED; return result
	result.data = _kv_data.duplicate(true)
	if not result.busy:
		var captured := _capture_world_state()
		if captured.ok and not captured.data.is_empty(): result.data["__world"] = captured.data
		elif not captured.ok: result.error = captured.error
	return result

func _debug_context_matches(request: Dictionary) -> bool:
	return request.get("protocol") == 2 and request.get("session") == get_instance_id() \
		and request.get("project") == ProjectSettings.globalize_path("res://") and request.get("root") == ProjectSettings.globalize_path(save_root) \
		and request.get("context") == get_active_context() and request.get("revision") == _runtime_revision \
		and not _load_active and not _has_pending_writes() and not _closing

func _apply_debug_v2(request: Dictionary) -> Error:
	if not _debug_context_matches(request): return ERR_BUSY
	if not request.get("operations") is Array: return ERR_INVALID_DATA
	for op in request.operations:
		if not op is Dictionary or not op.get("path") is Array or op.path.is_empty(): return ERR_INVALID_DATA
		if not op.path[0] is Dictionary or not op.path[0].has("key"): return ERR_INVALID_DATA
		if str(op.path[0].key) in ["__world", "__saveables"]: return ERR_UNAVAILABLE
		if op.get("action", "set") != "insert" and not op.has("before"): return ERR_INVALID_DATA
	var patched := SaveStateData.patch(_kv_data, request.operations)
	if patched.error != OK: return patched.error
	if SaveStateGenerationCodec.encode(patched.data).error != OK or not _validate_loaded_data(patched.data).is_empty(): return ERR_INVALID_DATA
	_kv_data = patched.data
	_runtime_revision += 1
	_touch_pending_dirty()
	return OK

func _debug_save_v2(request: Dictionary) -> void:
	if not _debug_context_matches(request):
		_send_debug_reply("result_v2", [int(request.get("id", -1)), ERR_BUSY, _runtime_revision, "disk"])
		return
	var result := await save_game()
	_send_debug_reply("result_v2", [int(request.get("id", -1)), result.error, _runtime_revision, "disk"])

func _send_debug_reply(message: String, data: Array) -> void:
	debug_reply.emit(message, data)
	if EngineDebugger.is_active():
		EngineDebugger.send_message("savestate_pro:" + message, data)


func _exit_tree() -> void:
	_closing = true
	if _debug_capture_registered:
		EngineDebugger.unregister_message_capture(&"savestate_pro")
		_debug_capture_registered = false


func _apply_kv_patch(patch: Dictionary) -> void:
	if patch.is_empty():
		return
	if not _hydrate_kv_if_needed():
		return
	for k in patch:
		_kv_data[k] = patch[k]
	_kv_hydrated = true
	_runtime_revision += 1
	_touch_pending_dirty()
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
## If [method register_key] was used, type must match or an error is logged and the write is skipped.
func set_value(key: StringName, value: Variant) -> void:
	if not _hydrate_kv_if_needed():
		return
	if _kv_types.has(key):
		var exp_type: int = int(_kv_types[key])
		if not _value_matches_registered_type(value, exp_type):
			push_error(
				"SaveState: set_value(%s) type mismatch — expected Variant.Type %s, got %s"
				% [str(key), str(exp_type), str(typeof(value))]
			)
			return
	_kv_data[key] = value
	_runtime_revision += 1
	_touch_pending_dirty()


func get_value(key: StringName, default: Variant = null) -> Variant:
	_hydrate_kv_if_needed()
	if _kv_data.has(key):
		return _kv_data[key]
	if _kv_registered_defaults.has(key):
		return _kv_registered_defaults[key]
	return default


## v1.2: lock a KV key to a [method @GlobalScope.typeof] and optional default (used when the key is absent after load).
## [param editor_value_hint]: [constant KV_EDITOR_HINT_AUTO] maps [constant TYPE_COLOR] → Save Browser color picker; use [constant KV_EDITOR_HINT_NONE] to skip.
func register_key(
		key: StringName,
		expected_type: int,
		default_value: Variant = null,
		editor_value_hint: int = KV_EDITOR_HINT_AUTO
	) -> void:
	_kv_types[key] = expected_type
	if typeof(default_value) != TYPE_NIL:
		if not _value_matches_registered_type(default_value, expected_type):
			push_warning("SaveState: register_key(%s) default value type does not match expected_type" % str(key))
		_kv_registered_defaults[key] = default_value
	var hint := editor_value_hint
	if hint == KV_EDITOR_HINT_AUTO:
		hint = KV_EDITOR_HINT_COLOR if expected_type == TYPE_COLOR else KV_EDITOR_HINT_NONE
	if hint != KV_EDITOR_HINT_NONE:
		register_editor_hint(str(key), hint)


func unregister_key(key: StringName) -> void:
	_kv_types.erase(key)
	_kv_registered_defaults.erase(key)
	_editor_flat_hints.erase(str(key))
	_save_editor_hints_to_disk()


## v1.2: Save Browser metadata for nested keys (dot path). [constant KV_EDITOR_HINT_COLOR] shows a color picker in the Data tab.
func register_editor_hint(flat_path: String, hint: int) -> void:
	if flat_path.is_empty():
		return
	_editor_flat_hints[flat_path] = hint
	_save_editor_hints_to_disk()


func unregister_editor_hint(flat_path: String) -> void:
	_editor_flat_hints.erase(flat_path)
	_save_editor_hints_to_disk()


func get_editor_hints_copy() -> Dictionary:
	return _editor_flat_hints.duplicate(true)


func _editor_hints_storage_path() -> String:
	return save_root.path_join(".savestate_editor_hints.json")


func _load_editor_hints_from_disk() -> void:
	var p := _editor_hints_storage_path()
	if not FileAccess.file_exists(p):
		return
	var txt := FileAccess.get_file_as_string(p)
	var j: Variant = JSON.parse_string(txt)
	if typeof(j) != TYPE_DICTIONARY:
		return
	for k in j:
		_editor_flat_hints[str(k)] = int(j[k])


func _save_editor_hints_to_disk() -> void:
	_ensure_save_root()
	var f := FileAccess.open(_editor_hints_storage_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_editor_flat_hints, "\t"))
	f.close()


## Snapshot current KV + [code]__saveables[/code] into [param slot_id] (creates slot file if needed).
func export_current_to_slot(slot_id: StringName) -> Error:
	if not _slots.has(slot_id):
		ensure_slot_for_file_base(slot_id, str(slot_id))
	var hydration_error := _prepare_kv_save(slot_id)
	if hydration_error != OK:
		return hydration_error
	var identities := validate_saveables()
	if not identities.ok: return _reject_save(slot_id, identities.error)
	var merged := _kv_data.duplicate(true)
	merged["__saveables"] = gather_saveable_snapshots()
	return save_to_slot_sync(slot_id, merged)


## Load [param slot_id] into runtime KV and apply saveables bundle.
func import_slot_into_runtime(slot_id: StringName) -> Error:
	return import_slot_into_runtime_result(slot_id).error


func import_slot_into_runtime_result(slot_id: StringName) -> SaveStateLoadResult:
	return _load_sync(slot_id, true, true)


## v1.2: ordered migration steps. Index [code]0[/code] runs when upgrading a file from schema 1 → 2, index [code]1[/code] for 2 → 3, etc. Each callable receives the inner [Dictionary] (mutate in place).
func set_schema_migrations(migrations: Array) -> void:
	_schema_migrations = migrations.duplicate()
	_migration_revision += 1


func clear_schema_migrations() -> void:
	_schema_migrations.clear()
	_migration_revision += 1


## v1.2: debounced autosave — call instead of [method persist] every frame. Batches rapid changes into one flush after [member auto_save_debounce_sec] seconds of quiet.
func mark_dirty() -> void:
	_runtime_revision += 1
	_dirty_revision = _runtime_revision
	if not _dirty_pending:
		_dirty_first_usec = Time.get_ticks_usec()
	_dirty_pending = true
	_dirty_last_usec = Time.get_ticks_usec()
	_dirty_retries = 0
	_schedule_dirty()


func is_dirty() -> bool:
	return _dirty_pending


func _touch_pending_dirty() -> void:
	if _dirty_pending:
		_dirty_revision = _runtime_revision
		_dirty_last_usec = Time.get_ticks_usec()
		_schedule_dirty()


func _schedule_dirty(delay: float = -1.0) -> void:
	if not _dirty_pending or _dirty_inflight or _closing or _dirty_timer == null:
		return
	if delay < 0.0:
		var now := Time.get_ticks_usec()
		var quiet_left := auto_save_debounce_sec - float(now - _dirty_last_usec) / 1000000.0
		var maximum_left := auto_save_max_interval_sec - float(now - _dirty_first_usec) / 1000000.0
		delay = minf(quiet_left, maximum_left)
	_dirty_timer.start(maxf(0.01, delay))


func _setup_dirty_timer() -> void:
	_dirty_timer = Timer.new()
	_dirty_timer.one_shot = true
	_dirty_timer.ignore_time_scale = true
	_dirty_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_dirty_timer)
	_dirty_timer.timeout.connect(_on_dirty_timer_timeout)


func _on_dirty_timer_timeout() -> void:
	if not _dirty_pending or _dirty_inflight or _closing:
		return
	_dirty_timer.stop()
	_dirty_inflight = true
	_auto_request = true
	_execute_debounced_persist()
	_auto_request = false


func _finish_dirty_job(job: Dictionary, error: Error) -> void:
	if job.get("auto", false):
		_dirty_inflight = false
	if error == OK and _save_job_matches_context(job) \
			and job.get("revision", -1) >= _dirty_revision and job.get("slot_id") == KV_SLOT_ID:
		_dirty_pending = false
		_dirty_retries = 0
		_dirty_timer.stop()
	if not _dirty_pending:
		return
	if error != OK and job.get("auto", false):
		_dirty_retries += 1
		if error in [ERR_BUSY, ERR_CANT_OPEN, ERR_CANT_CREATE, ERR_FILE_NOT_FOUND, ERR_FILE_CANT_OPEN, ERR_FILE_CANT_WRITE, ERR_UNAVAILABLE] \
				and _dirty_retries <= auto_save_retry_limit:
			_schedule_dirty(minf(5.0, auto_save_retry_base_sec * pow(2.0, _dirty_retries - 1)))
		else:
			_dirty_timer.stop()
			autosave_paused.emit(error)
	else:
		_schedule_dirty()


func _execute_debounced_persist() -> void:
	if dirty_persist_includes_saveables:
		var _e := persist_including_saveables()
	else:
		var _e2 := persist()


func _value_matches_registered_type(value: Variant, expected: int) -> bool:
	if expected == TYPE_NIL:
		return true
	var t := typeof(value)
	if t == expected:
		return true
	if expected == TYPE_FLOAT and t == TYPE_INT:
		return true
	if expected == TYPE_INT and t == TYPE_FLOAT:
		return true
	return false


func _run_schema_migration_pipeline(inner: Dictionary, file_schema: int) -> SaveStateLoadResult:
	var to_schema := get_current_schema_version()
	for ver in range(file_schema, to_schema):
		var idx := ver - 1
		var location := "migrations[%d]" % idx
		if idx >= _schema_migrations.size():
			return SaveStateLoadResult.failure(&"migration_missing", ERR_UNCONFIGURED,
				"Add a migration for schema %d to %d before loading this save." % [ver, ver + 1], location)
		var c: Variant = _schema_migrations[idx]
		if not (c is Callable) or not (c as Callable).is_valid():
			return SaveStateLoadResult.failure(&"migration_missing", ERR_UNCONFIGURED,
				"The migration for schema %d to %d is not callable." % [ver, ver + 1], location)
		var outcome: Variant = (c as Callable).call(inner)
		# Null preserves v1 mutate-in-place callbacks. New callbacks should return an explicit result.
		var accepted := outcome == null
		if outcome is bool:
			accepted = outcome
		elif outcome is int:
			accepted = outcome == OK
		elif outcome is Dictionary:
			accepted = outcome.get("ok") is bool and outcome.get("ok") == true
		if not accepted:
			return SaveStateLoadResult.failure(&"migration_failed", ERR_INVALID_DATA,
				"Migration from schema %d to %d failed. The save was not applied." % [ver, ver + 1], location)
	if file_schema < to_schema and not _default_state.is_empty():
		inner = SaveMigrator.deep_merge(inner, _default_state)
	return SaveStateLoadResult.success(inner, file_schema)


## v1.2: decode [param source_save_path] the same way runtime load does, then write prettified JSON to [param output_json_path] (UTF-8). Works with Pro encryption when running under Pro autoload.
func export_save_file_to_json(source_save_path: String, output_json_path: String) -> Error:
	if not FileAccess.file_exists(source_save_path):
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(source_save_path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var raw := file.get_buffer(file.get_length())
	file.close()
	var processed := _post_read_transform(raw)
	var pr := parse_save_file_buffer(processed)
	if not pr.get("ok", false):
		return int(pr.get("error", ERR_FILE_CORRUPT))
	var inner: Dictionary = pr["data"] as Dictionary
	var text: String = JSON.stringify(inner, "\t")
	var out := FileAccess.open(output_json_path, FileAccess.WRITE)
	if out == null:
		return FileAccess.get_open_error()
	out.store_string(text)
	out.close()
	return OK


## v1.2: resolve [param slot_id] to disk path under [member save_root], then [method export_save_file_to_json].
func export_slot_to_json(slot_id: StringName, output_json_path: String) -> Error:
	var slot: SaveSlot = _slots.get(slot_id) as SaveSlot
	if slot == null:
		return ERR_DOES_NOT_EXIST
	var path := slot.get_file_path(save_root, use_json)
	return export_save_file_to_json(path, output_json_path)


## Writes the KV dictionary to the reserved [member KV_SLOT_ID] file (sync, atomic).
func persist() -> Error:
	if _session_enabled():
		return _persist_playthrough(false).error
	var hydration_error := _prepare_kv_save(KV_SLOT_ID)
	if hydration_error != OK:
		return hydration_error
	if _session_enabled(): return _persist_playthrough(false).error
	return save_to_slot_sync(KV_SLOT_ID, _kv_data)


## Clears in-memory KV and will reload from disk on next access.
func clear_kv_cache() -> void:
	_kv_data.clear()
	_kv_hydrated = false
	_kv_load_failure = null
	_runtime_revision += 1
	_reset_dirty_context()


func replace_kv_data(data: Dictionary) -> void:
	_kv_data = data.duplicate(true)
	_kv_hydrated = true
	_kv_load_failure = null
	_runtime_revision += 1
	_reset_dirty_context()


func _reset_dirty_context() -> void:
	_cache_epoch += 1
	_dirty_pending = false
	_dirty_retries = 0
	if _dirty_timer != null:
		_dirty_timer.stop()


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
	if _session_enabled():
		return _persist_playthrough(true).error
	var hydration_error := _prepare_kv_save(KV_SLOT_ID)
	if hydration_error != OK:
		return hydration_error
	if _session_enabled(): return _persist_playthrough(true).error
	save_requested.emit()
	var identities := validate_saveables()
	if not identities.ok: return _reject_save(KV_SLOT_ID, identities.error)
	var merged := _kv_data.duplicate(true)
	merged["__saveables"] = gather_saveable_snapshots()
	return save_to_slot_sync(KV_SLOT_ID, merged)


## Loads slot data, emits [signal load_requested], applies [Saveable] snapshots under [code]__saveables[/code].
func load_from_slot_and_apply_saveables(slot_id: StringName) -> Dictionary:
	var result := _load_sync(slot_id, false, true)
	return result.data if result.ok else {}


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
	if not FileAccess.file_exists(path):
		if path.ends_with(".bak") or path.get_base_dir().simplify_path() != save_root.simplify_path():
			return ERR_INVALID_PARAMETER
		var base := path.get_file().get_basename()
		var slot_id := StringName(base)
		ensure_slot_for_file_base(slot_id, base)
		if get_slot(slot_id).get_file_path(save_root, use_json) != path:
			return ERR_INVALID_PARAMETER
		return save_to_slot_sync(slot_id, inner)
	return write_edited_data_to_disk(path, inner, FileAccess.get_sha256(path))


func write_edited_data_to_disk(path: String, inner: Dictionary, expected_hash: String) -> Error:
	if _has_pending_writes() or _load_active or _closing:
		return ERR_BUSY
	var lease := SaveStateCoordinator.acquire(save_root, get_instance_id())
	if lease.is_empty():
		return ERR_BUSY
	var error := _write_edited_data_to_disk_reserved(path, inner, expected_hash)
	SaveStateCoordinator.release(lease)
	return error


func _write_edited_data_to_disk_reserved(path: String, inner: Dictionary, expected_hash: String) -> Error:
	if path.ends_with(".bak") or expected_hash.is_empty():
		return ERR_INVALID_PARAMETER
	var read := _read_load_bytes(path)
	if int(read["error"]) != OK:
		return int(read["error"]) as Error
	var raw: PackedByteArray = read["raw"]
	if _bytes_hash(raw) != expected_hash:
		return ERR_BUSY
	var candidate := _decode_load_bytes(read, path)
	if not candidate.ok:
		return candidate.error
	var inner_header := SaveFormat.parse_header(_post_read_transform(raw))
	var encoded := _encode_save_data(inner, (int(inner_header.get("flags", 0)) & FLAG_JSON) != 0)
	if int(encoded["error"]) != OK:
		return int(encoded["error"]) as Error
	return AtomicWriter.write_atomic_if_unchanged(path, encoded["bytes"], backup_on_commit, expected_hash)


static func _bytes_hash(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func ensure_slot_for_file_base(slot_id: StringName, file_base: String) -> void:
	if _slots.has(slot_id):
		return
	var s := SaveSlot.new()
	s.slot_id = slot_id
	s.file_base_name = file_base
	s.display_name = str(file_base)
	register_slot(s)


func restore_from_backup_file(main_save_path: String) -> Error:
	if _has_pending_writes() or _load_active or _closing:
		return ERR_BUSY
	var lease := SaveStateCoordinator.acquire(save_root, get_instance_id())
	if lease.is_empty():
		return ERR_BUSY
	var error := _restore_from_backup_file_reserved(main_save_path)
	SaveStateCoordinator.release(lease)
	return error


func _restore_from_backup_file_reserved(main_save_path: String) -> Error:
	var backup := main_save_path + ".bak"
	var read := _read_load_bytes(backup)
	var result := _decode_load_bytes(read, backup)
	if not result.ok:
		return result.error
	# Keep the source backup intact; the writer retains the prior main until replacement succeeds.
	return AtomicWriter.write_atomic(main_save_path, read["raw"], false)


func create_backup_copy_for_file(main_save_path: String) -> Error:
	if _has_pending_writes() or _load_active or _closing:
		return ERR_BUSY
	var lease := SaveStateCoordinator.acquire(save_root, get_instance_id())
	if lease.is_empty():
		return ERR_BUSY
	var error := _create_backup_copy_for_file_reserved(main_save_path)
	SaveStateCoordinator.release(lease)
	return error


func _create_backup_copy_for_file_reserved(main_save_path: String) -> Error:
	if main_save_path.is_empty() or main_save_path.ends_with(".bak"):
		return ERR_INVALID_PARAMETER
	var read := _read_load_bytes(main_save_path)
	var result := _decode_load_bytes(read, main_save_path)
	if not result.ok:
		return result.error
	return AtomicWriter.write_atomic(main_save_path + ".bak", read["raw"], false)


func _hydrate_kv_if_needed() -> bool:
	if _kv_hydrated:
		return true
	if _session_enabled():
		var reloaded := _playthrough_session.load_slot(&"", false, true)
		if reloaded.ok:
			_last_load_result = SaveStateLoadResult.success(reloaded.data, reloaded.schema_version)
			return true
		_kv_load_failure = SaveStateLoadResult.failure(reloaded.status, reloaded.error, reloaded.message)
		_last_load_result = _kv_load_failure
		return false
	if DirAccess.dir_exists_absolute(save_root.path_join(".profiles")):
		var initialized := _session().start(true)
		if initialized.ok:
			_last_load_result = SaveStateLoadResult.success(initialized.data, initialized.schema_version)
			return true
		_kv_load_failure = SaveStateLoadResult.failure(initialized.status, initialized.error, initialized.message)
		_last_load_result = _kv_load_failure
		return false
	_register_reserved_kv_slot()
	var slot: SaveSlot = _slots[KV_SLOT_ID]
	var result := _read_load_candidate(slot.get_file_path(save_root, use_json))
	result.slot_id = KV_SLOT_ID
	_last_load_result = result
	if result.ok:
		replace_kv_data(result.data)
		return true
	if result.status == &"not_found":
		replace_kv_data({})
		return true
	_kv_load_failure = result
	return false


func _prepare_kv_save(slot_id: StringName) -> Error:
	if _hydrate_kv_if_needed():
		return OK
	return _reject_save(slot_id, _kv_load_failure.error)


func get_last_load_result() -> SaveStateLoadResult:
	return _last_load_result


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
	_migration_revision += 1


func get_current_schema_version() -> int:
	if ProjectSettings.has_setting(SETTING_SCHEMA_VERSION):
		return int(ProjectSettings.get_setting(SETTING_SCHEMA_VERSION))
	return 1


## Synchronous save (Lite). Override [method _pre_write_transform] in Pro for encryption.
func save_to_slot_sync(slot_id: StringName, data: Dictionary) -> Error:
	if _has_pending_writes() or _load_active or _closing:
		return _reject_save(slot_id, ERR_BUSY)
	_write_active = true
	var job := _prepare_save_job(slot_id, data)
	save_started.emit(slot_id)
	var error: Error = int(job["error"]) as Error
	if error == OK:
		error = AtomicWriter.write_atomic(job["path"], job["bytes"], job["backup"])
	_write_active = false
	_complete_save_job(job, error)
	return error


func _session() -> SaveStatePlaythroughSession:
	if _playthrough_session == null: _playthrough_session = SaveStatePlaythroughSession.new(self)
	return _playthrough_session


func _session_enabled() -> bool:
	return _playthrough_session != null and _playthrough_session.enabled


func supports_profiles() -> bool:
	return false


func start_session(allow_existing_legacy: bool = false) -> SaveStateResult:
	var result := _session().start(allow_existing_legacy)
	return _report_operation(_session().active_slot, result)


func get_active_context() -> Dictionary:
	return {"enabled": _session_enabled(), "profile_id": _session().active_profile, "slot_id": _session().active_slot,
		"epoch": _session().epoch, "unsaved_changes": _session().has_unsaved_changes()}


func save_game(slot: StringName = &"", include_saveables: bool = true) -> SaveStateResult:
	var job := _session().prepare_save(slot, include_saveables, supports_profiles())
	if not job.has("generation_job"): return _report_operation(slot, job["result"])
	var result: SaveStateResult = await _dispatch_playthrough_job(job)
	return _report_operation(job["slot_id"], result)


func _dispatch_playthrough_job(job: Dictionary) -> SaveStateResult:
	return _commit_playthrough_job(job)


func _commit_playthrough_job(job: Dictionary) -> SaveStateResult:
	var result: SaveStateResult = job["result"]
	if result.ok:
		SaveStateGenerationSession.refresh_prune(job)
		result = SaveStateGenerationStore.commit(job["worker"])
	return _finish_playthrough_job(job, result, false)


func _finish_playthrough_job(job: Dictionary, result: SaveStateResult, report: bool) -> SaveStateResult:
	SaveStateCoordinator.release(str(job.get("lease", "")))
	result.operation_id = job["operation_id"]
	result.slot_id = job["slot_id"]
	if result.ok:
		result.metadata = job["result"].metadata
		result.schema_version = job["schema"]
		result.timings_usec.merge(job["result"].timings_usec)
		result.warnings.append_array(job["result"].warnings)
	_session().complete(job, result)
	if job.has("request"):
		job["request"].result = result
		job["request"].finished.emit()
	return _report_operation(job["slot_id"], result) if report else result


func _persist_playthrough(include_saveables: bool) -> SaveStateResult:
	var job := _session().prepare_save(&"", include_saveables)
	var id: StringName = job.get("slot_id", _session().active_slot)
	save_started.emit(id)
	var result: SaveStateResult
	if job.has("generation_job"):
		result = _commit_playthrough_job(job)
	else:
		result = job["result"]
		_finish_dirty_job({"auto": _auto_request}, result.error)
	if result.ok: save_completed.emit(id)
	else: save_failed.emit(id, result.error)
	return _report_operation(id, result)


func load_game(slot: StringName = &"", allow_recovery: bool = false, discard_unsaved: bool = false) -> SaveStateResult:
	var result := _session().load_slot(slot, allow_recovery, discard_unsaved)
	return _report_operation(result.slot_id if result.ok else slot, result)


func new_playthrough(display_name: String = "New playthrough", initial_data: Dictionary = {}, discard_unsaved: bool = false) -> SaveStateResult:
	var result := _session().new_playthrough(display_name, initial_data, discard_unsaved)
	return _report_operation(result.slot_id, result)


func list_slots(include_deleted: bool = false, refresh: bool = false) -> SaveStateResult:
	return _report_operation(&"", _session().list_slots(include_deleted, refresh))


func rename_slot(slot: StringName, display_name: String) -> SaveStateResult:
	var result := _session().mutate_slot(slot, "rename", display_name)
	return _report_operation(result.slot_id, result)


func duplicate_slot(slot: StringName, display_name: String) -> SaveStateResult:
	var result := _session().mutate_slot(slot, "duplicate", display_name)
	return _report_operation(result.slot_id, result)


func delete_slot(slot: StringName) -> SaveStateResult:
	var result := _session().mutate_slot(slot, "delete")
	return _report_operation(result.slot_id, result)


func get_slot_preview(slot: StringName = &"") -> SaveStateResult:
	# Preview reads do not announce a save/load operation to gameplay listeners.
	return _session().slot_preview(slot)


func list_slot_history(slot: StringName = &"") -> SaveStateResult:
	var result := _session().slot_history(slot)
	return _report_operation(result.slot_id, result)


func recover_slot(slot: StringName, generation_id: String) -> SaveStateResult:
	var result := _session().recover_slot(slot, generation_id)
	return _report_operation(result.slot_id, result)


func update_slot_metadata(slot: StringName, changes: Dictionary) -> SaveStateResult:
	var result := _session().update_metadata(slot, changes)
	return _report_operation(result.slot_id, result)


func get_device_data() -> SaveStateResult:
	return _report_operation(&"", _session().device_data())


func set_device_data(data: Dictionary) -> SaveStateResult:
	return _report_operation(&"", _session().device_data(data))


func list_profiles(include_deleted: bool = false) -> SaveStateResult:
	return _report_operation(&"", _session().list_profiles(include_deleted))


func create_profile(display_name: String) -> SaveStateResult:
	return _report_operation(&"", _session().create_profile(display_name))


func switch_profile(profile: StringName, discard_unsaved: bool = false) -> SaveStateResult:
	var result := _session().switch_profile(profile, discard_unsaved)
	return _report_operation(result.slot_id, result)


func rename_profile(profile: StringName, display_name: String) -> SaveStateResult:
	return _report_operation(&"", _session().mutate_profile(profile, "rename", display_name))


func delete_profile(profile: StringName) -> SaveStateResult:
	return _report_operation(&"", _session().mutate_profile(profile, "delete"))


func get_profile_data() -> SaveStateResult:
	return _report_operation(&"", _session().profile_data())


func set_profile_data(data: Dictionary) -> SaveStateResult:
	return _report_operation(&"", _session().profile_data(data))


## Retained-generation APIs are explicit; legacy persist/save methods retain their file layout until a session starts.
func save_generation_sync(slot_id: StringName, data: Dictionary, thumbnail: PackedByteArray = PackedByteArray()) -> SaveStateResult:
	return _save_generation_options(slot_id, data, thumbnail, {})


func _save_generation_options(slot_id: StringName, data: Dictionary, thumbnail: PackedByteArray, options: Dictionary) -> SaveStateResult:
	if _has_pending_writes() or _load_active or _closing:
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_BUSY, "Another operation is in progress."))
	_write_active = true
	var job := SaveStateGenerationSession.prepare(self, slot_id, data, thumbnail, options)
	var result: SaveStateResult = job["result"]
	if result.ok:
		SaveStateGenerationSession.refresh_prune(job)
		result = SaveStateGenerationStore.commit(job["worker"])
	_write_active = false
	return _complete_generation_job(job, result)


func _complete_generation_job(job: Dictionary, result: SaveStateResult) -> SaveStateResult:
	if job.has("session_context"):
		return _finish_playthrough_job(job, result, not job.get("defer_report", false))
	SaveStateCoordinator.release(str(job.get("lease", "")))
	result.operation_id = job["operation_id"]
	if result.ok:
		var prepared: SaveStateResult = job["result"]
		result.warnings.append_array(prepared.warnings)
		result.timings_usec.merge(prepared.timings_usec)
		result.schema_version = prepared.schema_version
		result.metadata = prepared.metadata
		if str(prepared.metadata.get("source", "")).length() == 32:
			result.recovered_from = prepared.metadata["source"]
	result.timings_usec["total"] = Time.get_ticks_usec() - int(job["started"])
	return _report_operation(job["slot_id"], result)


func _report_operation(slot_id: StringName, result: SaveStateResult) -> SaveStateResult:
	if result.operation_id.is_empty():
		result.operation_id = SaveStateCoordinator.next_operation()
	result.slot_id = slot_id
	operation_finished.emit(result)
	return result


## Recovery is opt-in and only skips corrupt containers. Key/schema/I/O errors stop selection.
func load_generation_sync(slot_id: StringName, allow_recovery: bool = false, apply_runtime: bool = false) -> SaveStateResult:
	if _session_enabled() and apply_runtime:
		return _report_operation(slot_id, SaveStateResult.outcome(&"active_context", ERR_BUSY, "Use load_game() to change the active playthrough."))
	if _has_pending_writes() or _load_active or _closing:
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_BUSY, "Another operation is in progress."))
	_load_active = true
	var lease := SaveStateCoordinator.acquire(save_root, get_instance_id())
	var started := Time.get_ticks_usec()
	var context := [save_root, _runtime_revision, _migration_revision, get_current_schema_version(), _get_debug_crypto_keys()]
	var result := SaveStateGenerationSession.inspect(self, slot_id, allow_recovery)
	if context != [save_root, _runtime_revision, _migration_revision, get_current_schema_version(), _get_debug_crypto_keys()]:
		result = SaveStateGenerationSession.failure(ERR_BUSY, "State or configuration changed while validating the save. Load it again.")
	if result.ok and apply_runtime:
		# This API applies KV only. Managed world restoration belongs to the later world phase.
		var kv := result.data.duplicate(true)
		kv.erase("__saveables")
		replace_kv_data(kv)
	SaveStateCoordinator.release(lease)
	_load_active = false
	result.timings_usec["read_validate"] = Time.get_ticks_usec() - started
	return _report_operation(slot_id, result)


## Lists validation outcomes without applying migrations or changing runtime state.
func list_generations(slot_id: StringName) -> SaveStateResult:
	if _has_pending_writes() or _load_active or _closing:
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_BUSY, "Another operation is in progress."))
	var listing := SaveStateGenerationStore.scan(save_root, str(slot_id))
	if int(listing["error"]) != OK:
		return _report_operation(slot_id, SaveStateGenerationSession.failure(int(listing["error"]) as Error, "The generation directory could not be listed."))
	var entries: Array = []
	for file in listing["files"]:
		var inspected := SaveStateGenerationStore.read(file["path"], _get_debug_crypto_keys())
		if inspected.ok and inspected.slot_id != slot_id:
			inspected = SaveStateGenerationSession.failure(ERR_FILE_CORRUPT, "The generation belongs to another slot.")
		if inspected.ok and inspected.schema_version > get_current_schema_version():
			inspected = SaveStateResult.outcome(&"newer_schema", ERR_FILE_UNRECOGNIZED, "A newer game schema is required.")
		entries.append({"generation_id": file["id"], "sequence": file["sequence"], "status": inspected.status,
			"message": inspected.message, "schema_version": inspected.schema_version,
			"created_unix": inspected.metadata.get("created_unix", 0), "protected": inspected.metadata.get("protected", false),
			"thumbnail_available": not inspected.thumbnail.is_empty()})
	var result := SaveStateResult.outcome(&"ok", OK)
	result.data = {"generations": entries}
	return _report_operation(slot_id, result)


## Creates a new generation from selected history; the selected generation is never overwritten.
func recover_generation_sync(slot_id: StringName, generation_id: String) -> SaveStateResult:
	if generation_id.length() != 32 or not SaveStateGenerationCodec._hex(generation_id):
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Select a valid generation to recover."))
	if _has_pending_writes() or _load_active or _closing:
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_BUSY, "Another operation is in progress."))
	_load_active = true
	var lease := SaveStateCoordinator.acquire(save_root, get_instance_id())
	var candidate := SaveStateGenerationSession.inspect(self, slot_id, false, generation_id)
	SaveStateCoordinator.release(lease)
	_load_active = false
	if not candidate.ok:
		return _report_operation(slot_id, candidate)
	return _save_generation_options(slot_id, candidate.data, candidate.thumbnail, {"source": generation_id})


## Editor callers supply the generation observed when opening the document.
func edit_generation_sync(slot_id: StringName, data: Dictionary, expected_generation: String) -> SaveStateResult:
	if expected_generation.is_empty():
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Reload the generation before editing."))
	if SaveStateCoordinator.editor_game_running():
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_BUSY, "Stop the running game before editing a disk save."))
	if _has_pending_writes() or _load_active or _closing:
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_BUSY, "Another operation is in progress."))
	_load_active = true
	var lease := SaveStateCoordinator.acquire(save_root, get_instance_id())
	var candidate := SaveStateGenerationSession.inspect(self, slot_id, false, expected_generation)
	SaveStateCoordinator.release(lease)
	_load_active = false
	if not candidate.ok:
		return _report_operation(slot_id, candidate)
	return _save_generation_options(slot_id, data, candidate.thumbnail, {"expected_latest": expected_generation})


## Conversion keeps both the original file and a protected byte-for-byte copy.
func convert_legacy_sync(slot_id: StringName) -> SaveStateResult:
	if _has_pending_writes() or _load_active or _closing:
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_BUSY, "Another operation is in progress."))
	if not SaveStateGenerationStore.valid_id(str(slot_id)):
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Invalid slot ID."))
	var slot := _resolve_load_slot(slot_id, true)
	var path := slot.get_file_path(save_root, use_json)
	# Legacy registration can contain custom paths. Conversion only accepts files directly under this root.
	if SaveStateCoordinator.root_key(path.get_base_dir()) != SaveStateCoordinator.root_key(save_root):
		return _report_operation(slot_id, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "The legacy file must be inside the save root."))
	_load_active = true
	var lease := SaveStateCoordinator.acquire(save_root, get_instance_id())
	var read := _read_load_bytes(path)
	var candidate := _decode_load_bytes(read, path)
	var error := candidate.error
	var original := ""
	if candidate.ok:
		var folder := save_root.path_join("originals").path_join(str(slot_id))
		error = DirAccess.make_dir_recursive_absolute(folder)
		original = folder.path_join(_bytes_hash(read["raw"]) + ".original")
		if error == OK:
			if FileAccess.file_exists(original):
				error = OK if FileAccess.get_file_as_bytes(original) == read["raw"] else ERR_FILE_CORRUPT
			else:
				error = AtomicWriter.write_atomic(original, read["raw"])
	SaveStateCoordinator.release(lease)
	_load_active = false
	if not candidate.ok:
		return _report_operation(slot_id, candidate)
	if error != OK:
		return _report_operation(slot_id, SaveStateGenerationSession.failure(error, "The legacy original could not be preserved. Conversion stopped."))
	return _save_generation_options(slot_id, candidate.data, PackedByteArray(), {"protected": true, "source": original.get_file()})


func _has_pending_writes() -> bool:
	return _write_active or SaveStateCoordinator.occupied(save_root)


func _reject_save(slot_id: StringName, error: Error) -> Error:
	save_started.emit(slot_id)
	_finish_dirty_job({"auto": _auto_request}, error)
	save_failed.emit(slot_id, error)
	return error


func _prepare_save_job(slot_id: StringName, data: Dictionary) -> Dictionary:
	var job := {"error": OK, "slot_id": slot_id, "slot": _slots.get(slot_id), "root": save_root, "json": use_json,
		"revision": _runtime_revision, "epoch": _cache_epoch, "schema": get_current_schema_version(), "auto": _auto_request}
	if job["slot"] == null:
		job["error"] = ERR_DOES_NOT_EXIST
		return job
	var encoded := _encode_save_data(data, use_json)
	job["error"] = encoded["error"]
	if int(job["error"]) != OK:
		return job
	job["data"] = data.duplicate(true)
	job["bytes"] = encoded["bytes"]
	job["path"] = job["slot"].get_file_path(save_root, use_json)
	job["backup"] = backup_on_commit
	job["lease"] = SaveStateCoordinator.acquire(save_root, get_instance_id())
	if str(job["lease"]).is_empty():
		job["error"] = ERR_BUSY
	return job


func _encode_save_data(data: Dictionary, json_mode: bool) -> Dictionary:
	var config_error := _validate_write_configuration()
	if config_error != OK:
		return {"error": config_error}
	if not SaveStateData.invalid_path(data).is_empty() or not _validate_loaded_data(data).is_empty():
		return {"error": ERR_INVALID_DATA}
	var envelope := {"schema_version": get_current_schema_version(), "data": data}
	var payload := JSON.stringify(envelope).to_utf8_buffer() if json_mode else var_to_bytes(envelope)
	var bytes := _compose_file_bytes(FORMAT_VERSION, get_current_schema_version(), FLAG_JSON if json_mode else 0, payload)
	bytes = _pre_write_transform(bytes)
	if bytes.is_empty():
		return {"error": ERR_CANT_CREATE}
	if bytes.size() > 64 * 1024 * 1024:
		return {"error": ERR_OUT_OF_MEMORY}
	return {"error": OK, "bytes": bytes}


func _validate_write_configuration() -> Error:
	return OK


func _save_job_matches_context(job: Dictionary) -> bool:
	var slot: SaveSlot = job.get("slot") as SaveSlot
	return slot != null and job.get("epoch") == _cache_epoch and job.get("root") == save_root \
		and job.get("json") == use_json and _slots.get(job.get("slot_id")) == slot \
		and slot.get_file_path(save_root, use_json) == job.get("path")


func _complete_save_job(job: Dictionary, error: Error) -> void:
	SaveStateCoordinator.release(str(job.get("lease", "")))
	var slot_id: StringName = job["slot_id"]
	var same_context := _save_job_matches_context(job)
	_finish_dirty_job(job, error)
	if error == OK:
		var slot: SaveSlot = job["slot"]
		if same_context:
			slot.last_modified_unix = int(Time.get_unix_time_from_system())
			slot.file_schema_version = job["schema"]
		if slot_id == KV_SLOT_ID and same_context and job["revision"] == _runtime_revision:
			_kv_data = job["data"].duplicate(true)
			_kv_hydrated = true
			_runtime_revision += 1
		save_completed.emit(slot_id)
	else:
		save_failed.emit(slot_id, error)


func load_from_slot_sync(slot_id: StringName) -> Dictionary:
	var result := load_from_slot_result_sync(slot_id)
	return result.data if result.ok else {}


func load_from_slot_result_sync(slot_id: StringName) -> SaveStateLoadResult:
	return _load_sync(slot_id, false, false)


func _load_sync(slot_id: StringName, import_runtime: bool, apply_scene: bool) -> SaveStateLoadResult:
	if _session_enabled() and (import_runtime or apply_scene or slot_id == KV_SLOT_ID):
		load_started.emit(slot_id)
		return _report_load_result(slot_id, SaveStateLoadResult.failure(&"active_context", ERR_BUSY, "Use load_game() to change the active playthrough."))
	if _load_active or _has_pending_writes() or _closing:
		load_started.emit(slot_id)
		return _report_load_result(slot_id, SaveStateLoadResult.failure(&"busy", ERR_BUSY, "Another load is in progress."))
	_load_lease = SaveStateCoordinator.acquire(save_root, get_instance_id())
	_load_active = true
	load_started.emit(slot_id)
	var slot := _resolve_load_slot(slot_id, import_runtime)
	var result: SaveStateLoadResult
	if slot == null:
		result = SaveStateLoadResult.failure(&"not_found", ERR_DOES_NOT_EXIST, "The slot is not registered.")
	else:
		result = _read_load_candidate(slot.get_file_path(save_root, use_json))
	return _finish_load_result(slot_id, slot, result, import_runtime, apply_scene)


func _resolve_load_slot(slot_id: StringName, allow_unregistered: bool) -> SaveSlot:
	var slot: SaveSlot = _slots.get(slot_id) as SaveSlot
	if slot == null and allow_unregistered:
		slot = SaveSlot.new()
		slot.slot_id = slot_id
		slot.file_base_name = str(slot_id)
		slot.display_name = str(slot_id)
	return slot


func _finish_load_result(slot_id: StringName, slot: SaveSlot, result: SaveStateLoadResult,
		import_runtime: bool, apply_scene: bool) -> SaveStateLoadResult:
	if result.ok:
		# No cache, slot metadata, scene application, or success signal changes before this point.
		if not _slots.has(slot_id):
			register_slot(slot)
		slot.file_schema_version = result.schema_version
		if import_runtime:
			var kv := result.data.duplicate(true)
			kv.erase("__saveables")
			replace_kv_data(kv)
		elif slot_id == KV_SLOT_ID:
			replace_kv_data(result.data)
		if apply_scene:
			load_requested.emit()
			apply_saveables_from_bundle(result.data.get("__saveables", {}))
		if result.schema_version < get_current_schema_version():
			migration_required.emit(result.schema_version, get_current_schema_version())
	SaveStateCoordinator.release(_load_lease)
	_load_lease = ""
	_load_active = false
	return _report_load_result(slot_id, result)


func _report_load_result(slot_id: StringName, result: SaveStateLoadResult) -> SaveStateLoadResult:
	result.slot_id = slot_id
	_last_load_result = result
	if result.ok:
		load_completed.emit(slot_id, result.data.duplicate(true))
	else:
		load_failed.emit(slot_id, result.error)
	load_finished.emit(result)
	return result


func _read_load_candidate(path: String) -> SaveStateLoadResult:
	return _decode_load_bytes(_read_load_bytes(path), path)


## Worker-safe file read. Decoding and migration stay on the main thread.
static func _read_load_bytes(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": ERR_FILE_NOT_FOUND, "raw": PackedByteArray()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error(), "raw": PackedByteArray()}
	var length := file.get_length()
	if length > 64 * 1024 * 1024:
		file.close()
		return {"error": ERR_OUT_OF_MEMORY, "raw": PackedByteArray()}
	var raw := file.get_buffer(length)
	var err := file.get_error()
	file.close()
	if raw.size() != length:
		err = ERR_FILE_CORRUPT
	return {"error": err, "raw": raw}


func _decode_load_bytes(read: Dictionary, path: String) -> SaveStateLoadResult:
	var err: Error = int(read.get("error", ERR_FILE_CORRUPT)) as Error
	var result: SaveStateLoadResult
	if err == ERR_FILE_NOT_FOUND:
		result = SaveStateLoadResult.failure(&"not_found", err, "No save exists in this slot.")
	elif err != OK:
		result = SaveStateLoadResult.failure(&"io_error", err, "The save could not be read: %s." % error_string(err))
	else:
		result = _decode_save_candidate(read["raw"])
	result.path = path
	return result


func _decode_save_candidate(raw: PackedByteArray) -> SaveStateLoadResult:
	return _parse_load_candidate(_post_read_transform(raw))


## Parses decrypted/unwrapped file bytes (SSP1 inner format). Used by async load and tools.
func parse_save_file_buffer(processed: PackedByteArray) -> Dictionary:
	return _parse_load_candidate(processed).as_dictionary()


func _parse_load_candidate(bytes: PackedByteArray) -> SaveStateLoadResult:
	var header := SaveFormat.parse_header(bytes)
	if int(header.get("error", ERR_FILE_CORRUPT)) != OK:
		return SaveStateLoadResult.failure(&"corrupt", ERR_FILE_CORRUPT, "The save header is missing or invalid.")
	if int(header["format_version"]) != FORMAT_VERSION or (int(header["flags"]) & ~FLAG_JSON) != 0:
		return SaveStateLoadResult.failure(&"unsupported_format", ERR_FILE_UNRECOGNIZED, "This save uses an unsupported file format.")
	if bytes.size() != SaveFormat.HEADER_SIZE + int(header["payload_len"]) or bytes.size() > 64 * 1024 * 1024:
		return SaveStateLoadResult.failure(&"corrupt", ERR_FILE_CORRUPT, "The save length does not match its header.")
	var schema := int(header["schema_version"])
	if schema < 1:
		return SaveStateLoadResult.failure(&"corrupt", ERR_FILE_CORRUPT, "The save schema must be a positive integer.", "schema_version")
	var parsed := _parse_payload(bytes.slice(SaveFormat.HEADER_SIZE), int(header["flags"]))
	var envelope_schema: Variant = parsed.get("schema_version")
	if not (envelope_schema is int or envelope_schema is float) or envelope_schema != schema:
		return SaveStateLoadResult.failure(&"corrupt", ERR_FILE_CORRUPT, "The save schema does not match its header.", "schema_version")
	if not (parsed.get("data") is Dictionary):
		return SaveStateLoadResult.failure(&"invalid_data", ERR_INVALID_DATA, "The save payload must contain a data dictionary.", "data")
	if schema > get_current_schema_version():
		return SaveStateLoadResult.failure(&"newer_schema", ERR_FILE_UNRECOGNIZED,
			"This save requires schema %d; this project supports schema %d." % [schema, get_current_schema_version()], "schema_version")
	var candidate: Dictionary = parsed["data"].duplicate(true)
	var result := _run_schema_migration_pipeline(candidate, schema)
	if not result.ok:
		return result
	var invalid := _validate_loaded_data(result.data)
	if not invalid.is_empty():
		return SaveStateLoadResult.failure(&"invalid_data", ERR_INVALID_DATA, "The loaded data does not match the configured save data.", invalid)
	return result


func _validate_loaded_data(data: Dictionary) -> String:
	if data.has("__saveables"):
		if not (data["__saveables"] is Dictionary):
			return "data.__saveables"
		for key in data["__saveables"]:
			if not (data["__saveables"][key] is Dictionary):
				return "data.__saveables[%s]" % str(key)
	for key in _kv_types:
		if data.has(key) and not _value_matches_registered_type(data[key], int(_kv_types[key])):
			return "data[%s]" % str(key)
	return ""


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
		"source_hash": _bytes_hash(raw),
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
	out["encrypted_outer"] = int(out["format_version"]) == int(_EncryptedSaveReader.OUTER_FORMAT_VERSION)

	var processed := raw
	if bool(out["encrypted_outer"]):
		var keys := _get_debug_crypto_keys()
		var aes: PackedByteArray = keys.get("aes", PackedByteArray()) as PackedByteArray
		var hmac: PackedByteArray = keys.get("hmac", PackedByteArray()) as PackedByteArray
		out["keys_present"] = aes.size() == int(_EncryptedSaveReader.AES_KEY_SIZE) and not hmac.is_empty()
		if bool(out["keys_present"]):
			var opened: Dictionary = _EncryptedSaveReader.open_outer_save_file(raw, aes, hmac)
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


## Pro overrides these hooks; Lite rejects managed worlds rather than silently dropping them.
func _capture_world_state() -> SaveStateResult:
	return SaveStateResult.outcome(&"ok", OK)

func _stage_world_restore(data: Dictionary) -> SaveStateResult:
	if data.has("__world"):
		return SaveStateResult.outcome(&"unsupported_capability", ERR_UNAVAILABLE, "Configure a Pro managed world to restore this save.")
	return SaveStateResult.outcome(&"ok", OK)

func _commit_world_restore() -> void:
	pass

func _abort_world_restore() -> void:
	pass


func _stage_world_candidate(data: Dictionary) -> SaveStateResult:
	var context := [save_root, _runtime_revision, _migration_revision, get_current_schema_version(), _get_debug_crypto_keys()]
	var started := Time.get_ticks_usec()
	var result := _stage_world_restore(data)
	result.timings_usec["world_restore"] = Time.get_ticks_usec() - started
	if result.ok and context != [save_root, _runtime_revision, _migration_revision, get_current_schema_version(), _get_debug_crypto_keys()]:
		_abort_world_restore()
		return SaveStateResult.outcome(&"busy", ERR_BUSY, "State or configuration changed during world staging. Retry the load.")
	return result


## Basic collision diagnostics also apply to the Lite custom-snapshot contract.
func validate_saveables() -> SaveStateResult:
	var seen := {}
	if get_tree() == null: return SaveStateResult.outcome(&"ok", OK)
	for node in get_tree().get_nodes_in_group("savestate_saveable"):
		if not node.has_method("get_storage_key") or not node.has_method("collect_snapshot"): continue
		var key := str(node.get_storage_key())
		if key.is_empty() or seen.has(key):
			var result := SaveStateResult.outcome(&"duplicate_identity", ERR_INVALID_DATA, "Assign a unique nonempty storage key to every custom Saveable.")
			result.data_path = str(node.get_path())
			return result
		seen[key] = true
	return SaveStateResult.outcome(&"ok", OK)
