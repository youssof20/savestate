# SaveState Lite 2.0

A save system for Godot: named saves, checkpoints, autosave, recovery history, and an editor dock for inspecting data. Free and MIT licensed.

## Install

Copy `addons/savestate` into your project and enable **SaveState (Lite)** in **Project → Project Settings → Plugins**. This adds the `SaveManager` autoload and the **SaveState** dock.

To try the demo, open this repository's `project.godot` and press F5. The addon is already included. Move with the arrow keys, change a value, save, then restart to resume.

## First save

Attach this script to a Node and run its scene:

```gdscript
extends Node

func _ready() -> void:
    var started := SaveManager.start_session()
    if not started.ok:
        push_error(started.message)
        return

    var coins := int(SaveManager.get_value(&"coins", 0))
    print("Loaded coins: ", coins)
    SaveManager.set_value(&"coins", coins + 10)
    var saved := await SaveManager.save_game()
    if not saved.ok:
        push_error(saved.message)
        return
    print("Saved coins: ", coins + 10)
```

Run once to save 10 coins, then restart to load 10 and save 20. Open **SaveState → Saved games** to inspect the same data. The dock refreshes automatically.

## What changed in v2

- Named playthroughs and checkpoints with retained generations for recovery.
- Saves appear directly in the editor, with nested data and history inspection.
- Failed loads report errors instead of silently replacing state.
- Autosave batches changes, limits retries, and reports failures.
- The included demo opens directly from a checkout or release ZIP.

See the [usage guide](GUIDE.md) for checkpoints, saved node properties, recovery, and upgrading v1 projects.

Lite saves synchronously and its editor is read-only. [SaveState Pro](https://chuumberry.itch.io/savestate-pro) adds managed worlds, multiple profiles, visual editing/recovery, migration previews, background writes, and encryption. Pro includes the required Lite core.

Tested on Windows with Godot **4.5.2, 4.6.3, and 4.7.2**. See [LICENSE](LICENSE); retain its notice when redistributing the source.
