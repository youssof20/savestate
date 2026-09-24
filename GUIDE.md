# Using SaveState Lite

## Sessions and checkpoints

Call `SaveManager.start_session()` before using the session API. It creates the first playthrough or restores the selected save in the default profile. Check `result.ok` and display `result.message` on failure; a failed load is not a new game.

```gdscript
SaveManager.set_value(&"coins", 25)
var saved := await SaveManager.save_game(&"before_boss")
if not saved.ok:
    push_error(saved.message)

# Later, after the player chooses to load:
var loaded := SaveManager.load_game(&"before_boss")
if not loaded.ok:
    push_error(loaded.message)
```

A named save creates or updates a checkpoint without changing the active slot. Loading it selects it; subsequent unnamed saves update that checkpoint. If loading would discard changes, the result is `unsaved_changes`. Ask the player before retrying with `load_game(&"before_boss", false, true)`.

Use `savestate/save_root` in Project Settings or the dock's **Setup and validation** to share the same folder between game and editor. The default is `user://savestate`. **Open save folder** shows its location.

## Main calls

| Call | Purpose |
| --- | --- |
| `start_session()` | Create or restore the session. |
| `set_value(key, value)` / `get_value(key, fallback)` | Write/read key-value state. |
| `register_key(key, type, default)` | Declare a key's expected type and default. |
| `save_game(slot = &"")` | Save the active playthrough or a named checkpoint. |
| `load_game(slot = &"", allow_recovery = false, discard_unsaved = false)` | Validate and load a save. |
| `new_playthrough(name, initial_data = {}, discard_unsaved = false)` | Create and select independent state. |
| `list_slots()` | Read catalogue entries from `result.data.entries`. |
| `rename_slot(slot, name)` / `duplicate_slot(slot, name)` | Rename or copy committed state. |
| `delete_slot(slot)` | Hide a non-active save while retaining files. |
| `list_slot_history(slot = &"")` | Read `result.data.generations`. |
| `recover_slot(slot, generation_id)` | Append a recovered generation; load it separately. |
| `get_profile_data()` / `set_profile_data(data)` | Progression shared across the default profile's saves. |
| `get_device_data()` / `set_device_data(data)` | Settings independent of a playthrough. |

Session operations return `SaveStateResult`. Check `ok`, `status`, `message`, and `data_path` when handling errors. Lite writes synchronously; `await save_game()` also works if you later use Pro.

Aliases accept lowercase letters, numbers, underscores, and hyphens, up to 64 characters; reserved device names are excluded. Display labels allow up to 80 characters. Names are not file paths.

## Autosave and node properties

Call `SaveManager.mark_dirty()` after meaningful changes. `auto_save_debounce_sec` sets the quiet interval; `auto_save_max_interval_sec` bounds the wait during continued changes. Listen to `operation_finished` for results and `autosave_paused` for repeated failures.

Add a **SaveComponent** child to a node. Set a unique `storage_key` and list the parent's properties in `tracked_properties`. `save_game()` includes those snapshots. `load_game()` applies them to registered nodes; call it after those nodes exist. Selected node changes need an explicit dirty mark for autosave.

**CollectionLink** records collected IDs. Its removal target defaults to itself; choose Parent when the helper belongs beneath a pickup. Lite does not reconstruct arbitrary scenes or respawn missing objects. Use your own scene logic for that, or Pro's managed-world integration.

## Inspect and recover

Double-click a save in the **SaveState** dock to browse nested fields. **History** shows retained generations; **Details** provides diagnostics and debug JSON export. Lite's inspector is read-only. Debug JSON is for inspection, not save re-import.

Recover in game code with `list_slot_history()` and `recover_slot()`, checking each result. Recovery writes a new latest generation; call `load_game()` to apply it. History defaults to five generations (`generation_retention`, minimum two). Keep external backups for long-term recovery.

For a small runtime menu, instance `addons/savestate/templates/save_menu_lite.tscn` after starting the session. Your game owns the pause/input policy.

## Upgrading

Back up your project and saves before replacing the addon folder. Existing low-level methods such as `persist()` remain available. V2 sessions are an explicit integration.

If `start_session()` returns `legacy_present`, load the chosen legacy save through the old API and check success. Call `start_session(true)` to adopt the hydrated state into separate session storage. Original files remain. Decide explicitly which other legacy slots to import.

For a schema change, create a shared setup script:

```gdscript
extends RefCounted

func configure(manager: SaveManagerBase) -> void:
    manager.set_schema_migrations([upgrade_1_to_2])

func upgrade_1_to_2(data: Dictionary) -> bool:
    data["inventory"] = data.get("inventory", [])
    return true
```

Set `savestate/schema_setup_script` to that script and `savestate/current_version` to 2 for this example. Restart the project. Migration index zero handles 1 → 2, index one handles 2 → 3. Callbacks must transform only the supplied dictionary, without changing globals, writing files, or making network requests.

## Limits

Save bounded plain dictionaries/arrays and supported native values, not arbitrary Objects, scripts, cycles, or running code. Failed validation is reported without replacing accepted state. Lite has one profile; Pro-only profile operations return `unsupported_capability`.

The catalogue supports up to 128 slot directories, including deleted saves. Deleted aliases remain reserved. Retained generations help recover from interrupted writes; they do not guarantee survival of power loss or concurrent processes writing the same folder.

Windows tests cover Godot 4.5.2, 4.6.3, and 4.7.2. Other platforms are not certified by those checks.
