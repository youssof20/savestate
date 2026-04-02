# Schema migration (Lite)

## Built-in forward merge

Project setting **`savestate/current_version`** is the live schema version. When a file on disk has an older embedded schema, `SaveManager` merges missing keys from the dictionary passed to **`set_default_state_for_migration()`** using `SaveMigrator.deep_merge`, so existing player files still load and pick up defaults for new fields.

## `migration_required` signal

When **`load_from_slot_sync`** successfully reads a file whose embedded schema is **strictly less than** `get_current_schema_version()`, Lite emits:

```gdscript
migration_required(old_schema_version: int, new_schema_version: int)
```

Hook it to run **your own** renames, value clamping, or one-time repairs — no Pro purchase required.

```gdscript
func _ready() -> void:
    SaveManager.migration_required.connect(_on_migration_required)

func _on_migration_required(old_v: int, new_v: int) -> void:
    if old_v == 1 and new_v >= 2:
        # Example: move a renamed key
        var x := SaveManager.get_value(&"old_key", null)
        if x != null:
            SaveManager.set_value(&"new_key", x)
```

Emit happens **after** parse succeeds and **before** `load_completed` for that load path (same frame). Defaults from `set_default_state_for_migration` may already have been merged inside `parse_save_file_buffer`; your handler can still adjust KV or slot data and call `persist()` if you need to rewrite disk immediately.

## Bumping version

1. Increase **`savestate/current_version`** in Project Settings.
2. Extend **`set_default_state_for_migration`** with defaults for new keys.
3. Optionally handle **`migration_required`** for non-trivial transforms.

SaveState Pro adds editor tooling for migration workflows; Lite remains fully capable of manual migration via the signal above.
