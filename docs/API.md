# SaveState Lite — API reference

All methods below are on the **SaveManager** autoload (`SaveManagerBase` in code). Only user-facing methods are listed (no leading underscore).

## set_value

```gdscript
func set_value(key: StringName, value: Variant) -> void
```

Stores a key in the in-memory KV map for the reserved `slot_0` store. Does not touch disk until `persist()`.

```gdscript
SaveManager.set_value(&"score", 9999)
```

## get_value

```gdscript
func get_value(key: StringName, default: Variant = null) -> Variant
```

Returns a value from the KV map, or `default` if missing.

```gdscript
var s := int(SaveManager.get_value(&"score", 0))
```

## persist

```gdscript
func persist() -> Error
```

Writes the current KV dictionary to the `slot_0` file using the atomic writer.

```gdscript
if SaveManager.persist() != OK:
    push_error("Save failed")
```

## clear_kv_cache

```gdscript
func clear_kv_cache() -> void
```

Clears in-memory KV data so the next access reloads from disk.

```gdscript
SaveManager.clear_kv_cache()
```

## replace_kv_data

```gdscript
func replace_kv_data(data: Dictionary) -> void
```

Replaces the entire KV dictionary in memory. Does not write until `persist()`.

```gdscript
SaveManager.replace_kv_data({"a": 1, "b": 2})
```

## gather_saveable_snapshots

```gdscript
func gather_saveable_snapshots() -> Dictionary
```

Collects `collect_snapshot()` from all nodes in group `savestate_saveable` that expose the required methods.

```gdscript
var bundle := SaveManager.gather_saveable_snapshots()
```

## persist_including_saveables

```gdscript
func persist_including_saveables() -> Error
```

Merges KV data with `__saveables` snapshots and writes `slot_0`.

```gdscript
SaveManager.persist_including_saveables()
```

## load_from_slot_and_apply_saveables

```gdscript
func load_from_slot_and_apply_saveables(slot_id: StringName) -> Dictionary
```

Loads a slot and applies `__saveables` entries to registered nodes.

```gdscript
var inner := SaveManager.load_from_slot_and_apply_saveables(&"slot_0")
```

## apply_saveables_from_bundle

```gdscript
func apply_saveables_from_bundle(bundle: Dictionary) -> void
```

Applies a previously stored `__saveables` dictionary to scene nodes.

```gdscript
SaveManager.apply_saveables_from_bundle(saved["__saveables"])
```

## write_inner_data_to_disk

```gdscript
func write_inner_data_to_disk(path: String, inner: Dictionary) -> Error
```

Writes a raw inner dictionary to a path derived from the file name (used by editor tools and advanced flows).

```gdscript
SaveManager.write_inner_data_to_disk("user://savestate/slot_0.bin", data)
```

## ensure_slot_for_file_base

```gdscript
func ensure_slot_for_file_base(slot_id: StringName, file_base: String) -> void
```

Registers a `SaveSlot` for a base file name if missing.

```gdscript
SaveManager.ensure_slot_for_file_base(&"myslot", "myslot")
```

## restore_from_backup_file

```gdscript
func restore_from_backup_file(main_save_path: String) -> Error
```

Replaces the main file with its `.bak` sibling if present.

```gdscript
SaveManager.restore_from_backup_file("user://savestate/slot_0.bin")
```

## create_backup_copy_for_file

```gdscript
func create_backup_copy_for_file(main_save_path: String) -> Error
```

Copies the main save bytes to `main_save_path + ".bak"` (replaces an existing `.bak`). Does not modify the main file. Used by the Save Browser **Backup selected** button and for slots that have no rolling backup yet.

```gdscript
SaveManager.create_backup_copy_for_file("user://savestate/slot_2.bin")
```

## register_slot

```gdscript
func register_slot(slot: SaveSlot) -> void
```

Registers a `SaveSlot` resource for use with sync load and save.

```gdscript
SaveManager.register_slot(my_slot_resource)
```

## unregister_slot

```gdscript
func unregister_slot(slot_id: StringName) -> void
```

Removes a slot from the registry.

```gdscript
SaveManager.unregister_slot(&"old_slot")
```

## get_slot

```gdscript
func get_slot(slot_id: StringName) -> SaveSlot
```

Returns the `SaveSlot` for an id, or `null`.

```gdscript
var sl := SaveManager.get_slot(&"slot_1")
```

## set_default_state_for_migration

```gdscript
func set_default_state_for_migration(defaults: Dictionary) -> void
```

Sets default key structure used when merging older saves forward.

```gdscript
SaveManager.set_default_state_for_migration({"new_stat": 0})
```

## get_current_schema_version

```gdscript
func get_current_schema_version() -> int
```

Returns `savestate/current_version` from Project Settings (defaults to 1).

```gdscript
var v := SaveManager.get_current_schema_version()
```

## save_to_slot_sync

```gdscript
func save_to_slot_sync(slot_id: StringName, data: Dictionary) -> Error
```

Synchronously serializes and writes one slot file.

```gdscript
SaveManager.save_to_slot_sync(&"autosave", {"t": Time.get_ticks_msec()})
```

## load_from_slot_sync

```gdscript
func load_from_slot_sync(slot_id: StringName) -> Dictionary
```

Synchronously reads and parses one slot file into the inner data dictionary.

```gdscript
var d := SaveManager.load_from_slot_sync(&"autosave")
```

## parse_save_file_buffer

```gdscript
func parse_save_file_buffer(processed: PackedByteArray) -> Dictionary
```

Parses decrypted inner file bytes into `ok` / `data` / `schema_version` (used by tools and advanced loaders).

```gdscript
var pr := SaveManager.parse_save_file_buffer(bytes)
```

## debug_inspect_save_path

```gdscript
func debug_inspect_save_path(path: String) -> Dictionary
```

Editor-oriented: reads a file from disk and returns previews and parsed inner dict for the Save Browser dock.

```gdscript
var info := SaveManager.debug_inspect_save_path("user://savestate/slot_0.bin")
```

## debug_health_for_path

```gdscript
func debug_health_for_path(path: String) -> Dictionary
```

Returns a summary dict (size, schema, encryption hints when Pro keys exist) for UI badges.

```gdscript
var h := SaveManager.debug_health_for_path(path)
```

## register_key (v1.2)

```gdscript
func register_key(
    key: StringName,
    expected_type: int,
    default_value: Variant = null,
    editor_value_hint: int = SaveManager.KV_EDITOR_HINT_AUTO
) -> void
```

Locks a KV key to a `typeof` value. `set_value` rejects mismatched types (int/float relaxed). Missing keys fall back to `default_value` in `get_value`. With `TYPE_COLOR` and `KV_EDITOR_HINT_AUTO`, the Save Browser Data tab shows a color picker; use `KV_EDITOR_HINT_NONE` to hide it for ambiguous nested values.

```gdscript
SaveManager.register_key(&"gold", TYPE_INT, 0)
SaveManager.register_key(&"tint", TYPE_COLOR, Color.WHITE)
```

## unregister_key (v1.2)

```gdscript
func unregister_key(key: StringName) -> void
```

## set_schema_migrations (v1.2)

```gdscript
func set_schema_migrations(migrations: Array) -> void
```

Ordered callables. Entry at index `0` runs when upgrading a file from schema **1 → 2**, index `1` for **2 → 3**, etc. Each callable receives the inner `Dictionary` (mutate in place).

```gdscript
SaveManager.set_schema_migrations([
    func(d): d["mana"] = d.get("mana", 100),
    func(d): d.erase("legacy_key"),
])
```

## mark_dirty (v1.2)

```gdscript
func mark_dirty() -> void
```

Debounced persist after `auto_save_debounce_sec` seconds of quiet. Pro autoload uses async persist.

## SaveStateUnixDisplay (v1.2)

Global class `addons/savestate/unix_display.gd`. Formats Unix seconds (e.g. from `FileAccess.get_modified_time`) for labels. Wraps `Time.get_datetime_string_from_unix_time`; the optional `use_space_separator` argument is the engine’s **use_space** flag (date/time separator), not a UTC toggle.

```gdscript
var label := SaveStateUnixDisplay.format_modified_time(int(FileAccess.get_modified_time(path)))
if label.is_empty():
    label = "—"
```

## register_editor_hint (v1.2)

```gdscript
func register_editor_hint(flat_path: String, hint: int) -> void
```

Flat dot-path (same as Save Browser Data tab) → `SaveManager.KV_EDITOR_HINT_COLOR` (`1`) so the dock shows a color picker. Persisted under `save_root/.savestate_editor_hints.json`.

## get_editor_hints_copy (v1.2)

```gdscript
func get_editor_hints_copy() -> Dictionary
```

## export_current_to_slot / import_slot_into_runtime (v1.2)

```gdscript
func export_current_to_slot(slot_id: StringName) -> Error
func import_slot_into_runtime(slot_id: StringName) -> Error
```

## export_save_file_to_json / export_slot_to_json (v1.2)

```gdscript
func export_save_file_to_json(source_save_path: String, output_json_path: String) -> Error
func export_slot_to_json(slot_id: StringName, output_json_path: String) -> Error
```

## Signals

| Signal | When |
|--------|------|
| `save_started` / `save_completed` / `save_failed` | Slot save lifecycle |
| `load_started` / `load_completed` / `load_failed` | Slot load lifecycle |
| `save_requested` / `load_requested` | KV + saveables flows |
| `migration_required(old_schema_version, new_schema_version)` | Loaded file schema is older than `savestate/current_version` |

See [MIGRATION.md](MIGRATION.md) for `migration_required`.
