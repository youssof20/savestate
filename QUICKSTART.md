# Quick start

## First save (key-value)

```gdscript
SaveManager.set_value(&"player_gold", 100)
SaveManager.persist()
```

## First load (key-value)

```gdscript
var g := int(SaveManager.get_value(&"player_gold", 0))
```

## Mark a node for saving (Lite)

Add the node to group `savestate_saveable`. Implement:

```gdscript
func get_storage_key() -> StringName:
    return &"player"
func collect_snapshot() -> Dictionary:
    return {"hp": hp, "pos": global_position}
func apply_snapshot(data: Dictionary) -> void:
    if data.has("hp"): hp = int(data["hp"])
    if data.has("pos"): global_position = data["pos"]
```

Then `SaveManager.persist_including_saveables()`.

## Restore from backup

Save Browser: **Restore from .bak**, or:

```gdscript
SaveManager.restore_from_backup_file("user://savestate/slot_0.bin")
```

## New field after old saves exist

Bump `savestate/current_version`, then:

```gdscript
SaveManager.set_default_state_for_migration({"new_stat": 0})
```

Load as usual.

## Named slot

```gdscript
SaveManager.save_to_slot_sync(&"slot_2", {"k": 1})
var d := SaveManager.load_from_slot_sync(&"slot_2")
```

Pro: [chuumberry.itch.io/savestate-pro](https://chuumberry.itch.io/savestate-pro)
