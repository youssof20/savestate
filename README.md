SaveState Lite is a Godot 4 addon that writes save files atomically, keeps rolling backups, migrates older saves when you bump schema version, and exposes a single `SaveManager` autoload for key-value data and named slots. It is for projects that want safer disk saves than ad-hoc `FileAccess` without building a custom format from scratch.

## Installation

1. Copy the `addons/savestate/` folder into your Godot project (merge with your existing `addons/` folder).
2. Open **Project** → **Project Settings** → **Plugins**, find **SaveState (Lite)**, and enable it.
3. The plugin registers the **SaveManager** autoload (`res://addons/savestate/save_manager.gd`). You can call `SaveManager` from any script without further setup.

## Quick start

Store and flush simple stats to the built-in key-value file (`slot_0` on disk).

```gdscript
SaveManager.set_value(&"player_gold", 250)
SaveManager.persist()
```

Read a value back, using a default if the key was never saved.

```gdscript
var player_gold := int(SaveManager.get_value(&"player_gold", 0))
```

Save a full dictionary to a named slot (creates `slot_1.bin` or `.json` under `save_root`).

```gdscript
SaveManager.save_to_slot_sync(&"slot_1", {"player_health": 100, "player_level": 5})
```

Load that slot back into a dictionary.

```gdscript
var data := SaveManager.load_from_slot_sync(&"slot_1")
```

## Saving nodes (component snapshots)

Lite does not ship a `Saveable` node type in this addon folder. It does support **optional** scene data: any `Node` in group `savestate_saveable` that implements **`get_storage_key()`**, **`collect_snapshot()`**, and **`apply_snapshot(data: Dictionary)`** can participate when you call `persist_including_saveables()` or `load_from_slot_and_apply_saveables()`. You implement those three methods on your own script, add the node to the group, and merge snapshots into the `slot_0` payload under `__saveables`.

The **Saveable** node class, checkbox property picker in the inspector, and related Pro tooling ship with **SaveState Pro** (paid addon), not with this GitHub repo. On Lite alone, use the pattern above or write a thin helper node yourself.

Example parent script with three exported fields you might snapshot from a companion script:

```gdscript
extends CharacterBody2D
@export var player_health: int = 100
@export var player_gold: int = 0
@export var current_level: int = 1
```

A separate snapshot child would read those properties in `collect_snapshot()` and write them in `apply_snapshot()`. With **SaveState Pro**, you attach the official **Saveable** child and tick the matching properties in the inspector instead of hand-writing that bridge.

## Atomic writes

Each save writes the full file to a temporary path, checks the bytes, then replaces the real file in one step. If the process or OS stops halfway through a write, you do not get a half-old, half-new file: the previous file stays valid until the new one is committed.

Rolling backups: when `backup_on_commit` is true (default), the previous main file is renamed to `.bak` before the new data lands, so you can recover from bad writes or bad edits.

If you need encryption, async saves, viewport thumbnails, and the full **Save Browser** editor dock with live editing, those ship in **SaveState Pro**: [https://chuumberry.itch.io/savestate-pro](https://chuumberry.itch.io/savestate-pro)

## Schema migration

Project setting `savestate/current_version` is the live schema version. When a file on disk has an older embedded schema, `SaveManager` merges missing keys from the dictionary you passed to `set_default_state_for_migration()` using `SaveMigrator.deep_merge`, so existing player files still load and pick up defaults for new fields without throwing errors.

## API reference

All methods below are on the **SaveManager** autoload (`SaveManagerBase` in code). Only user-facing methods are listed (no leading underscore).

### set_value

```gdscript
func set_value(key: StringName, value: Variant) -> void
```

Stores a key in the in-memory KV map for the reserved `slot_0` store. Does not touch disk until `persist()`.

```gdscript
SaveManager.set_value(&"score", 9999)
```

### get_value

```gdscript
func get_value(key: StringName, default: Variant = null) -> Variant
```

Returns a value from the KV map, or `default` if missing.

```gdscript
var s := int(SaveManager.get_value(&"score", 0))
```

### persist

```gdscript
func persist() -> Error
```

Writes the current KV dictionary to the `slot_0` file using the atomic writer.

```gdscript
if SaveManager.persist() != OK:
    push_error("Save failed")
```

### clear_kv_cache

```gdscript
func clear_kv_cache() -> void
```

Clears in-memory KV data so the next access reloads from disk.

```gdscript
SaveManager.clear_kv_cache()
```

### replace_kv_data

```gdscript
func replace_kv_data(data: Dictionary) -> void
```

Replaces the entire KV dictionary in memory. Does not write until `persist()`.

```gdscript
SaveManager.replace_kv_data({"a": 1, "b": 2})
```

### gather_saveable_snapshots

```gdscript
func gather_saveable_snapshots() -> Dictionary
```

Collects `collect_snapshot()` from all nodes in group `savestate_saveable` that expose the required methods.

```gdscript
var bundle := SaveManager.gather_saveable_snapshots()
```

### persist_including_saveables

```gdscript
func persist_including_saveables() -> Error
```

Merges KV data with `__saveables` snapshots and writes `slot_0`.

```gdscript
SaveManager.persist_including_saveables()
```

### load_from_slot_and_apply_saveables

```gdscript
func load_from_slot_and_apply_saveables(slot_id: StringName) -> Dictionary
```

Loads a slot and applies `__saveables` entries to registered nodes.

```gdscript
var inner := SaveManager.load_from_slot_and_apply_saveables(&"slot_0")
```

### apply_saveables_from_bundle

```gdscript
func apply_saveables_from_bundle(bundle: Dictionary) -> void
```

Applies a previously stored `__saveables` dictionary to scene nodes.

```gdscript
SaveManager.apply_saveables_from_bundle(saved["__saveables"])
```

### write_inner_data_to_disk

```gdscript
func write_inner_data_to_disk(path: String, inner: Dictionary) -> Error
```

Writes a raw inner dictionary to a path derived from the file name (used by editor tools and advanced flows).

```gdscript
SaveManager.write_inner_data_to_disk("user://savestate/slot_0.bin", data)
```

### ensure_slot_for_file_base

```gdscript
func ensure_slot_for_file_base(slot_id: StringName, file_base: String) -> void
```

Registers a `SaveSlot` for a base file name if missing.

```gdscript
SaveManager.ensure_slot_for_file_base(&"myslot", "myslot")
```

### restore_from_backup_file

```gdscript
func restore_from_backup_file(main_save_path: String) -> Error
```

Replaces the main file with its `.bak` sibling if present.

```gdscript
SaveManager.restore_from_backup_file("user://savestate/slot_0.bin")
```

### register_slot

```gdscript
func register_slot(slot: SaveSlot) -> void
```

Registers a `SaveSlot` resource for use with sync load and save.

```gdscript
SaveManager.register_slot(my_slot_resource)
```

### unregister_slot

```gdscript
func unregister_slot(slot_id: StringName) -> void
```

Removes a slot from the registry.

```gdscript
SaveManager.unregister_slot(&"old_slot")
```

### get_slot

```gdscript
func get_slot(slot_id: StringName) -> SaveSlot
```

Returns the `SaveSlot` for an id, or `null`.

```gdscript
var sl := SaveManager.get_slot(&"slot_1")
```

### set_default_state_for_migration

```gdscript
func set_default_state_for_migration(defaults: Dictionary) -> void
```

Sets default key structure used when merging older saves forward.

```gdscript
SaveManager.set_default_state_for_migration({"new_stat": 0})
```

### get_current_schema_version

```gdscript
func get_current_schema_version() -> int
```

Returns `savestate/current_version` from Project Settings (defaults to 1).

```gdscript
var v := SaveManager.get_current_schema_version()
```

### save_to_slot_sync

```gdscript
func save_to_slot_sync(slot_id: StringName, data: Dictionary) -> Error
```

Synchronously serializes and writes one slot file.

```gdscript
SaveManager.save_to_slot_sync(&"autosave", {"t": Time.get_ticks_msec()})
```

### load_from_slot_sync

```gdscript
func load_from_slot_sync(slot_id: StringName) -> Dictionary
```

Synchronously reads and parses one slot file into the inner data dictionary.

```gdscript
var d := SaveManager.load_from_slot_sync(&"autosave")
```

### parse_save_file_buffer

```gdscript
func parse_save_file_buffer(processed: PackedByteArray) -> Dictionary
```

Parses decrypted inner file bytes into `ok` / `data` / `schema_version` (used by tools and advanced loaders).

```gdscript
var pr := SaveManager.parse_save_file_buffer(bytes)
```

### debug_inspect_save_path

```gdscript
func debug_inspect_save_path(path: String) -> Dictionary
```

Editor-oriented: reads a file from disk and returns previews and parsed inner dict for the Save Browser dock.

```gdscript
var info := SaveManager.debug_inspect_save_path("user://savestate/slot_0.bin")
```

### debug_health_for_path

```gdscript
func debug_health_for_path(path: String) -> Dictionary
```

Returns a summary dict (size, schema, encryption hints when Pro keys exist) for UI badges.

```gdscript
var h := SaveManager.debug_health_for_path(path)
```

## Pro version

SaveState Pro builds on this Lite addon. It swaps the autoload script for `pro_manager.gd`, adds async save and load on a worker thread, AES-256 plus HMAC encryption with one-click key generation in Project Settings, viewport thumbnail capture next to save files, a **Save Browser** dock with Explorer, Data, and Config tabs, live data editing while the game runs with debugger support, a **Saveable** inspector with checkbox UI for parent properties, and a **Quick Setup** entry in the editor tool menu. Pro is **$9.99** at launch: [https://chuumberry.itch.io/savestate-pro](https://chuumberry.itch.io/savestate-pro)

## Godot version support

Godot **4.3**, **4.4**, **4.5**, **4.6** tested and supported.

## License

Lite is MIT licensed. Use it in any project, commercial or otherwise, with no attribution required.
