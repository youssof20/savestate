# SaveState — minimal starter sample

Godot **4.3+** project: move with arrow keys, tweak **gold**, **XP**, **stash** (herbs/potions in one Dictionary), **player color**, and **position** — then **Save (slot_0)** / **Load (slot_0)**. Use the **line edit + “Next free”** and **Save copy to named slot** to write `slot_2.bin`, `checkpoint_boss.bin`, etc. without overwriting `slot_0`. `main.gd` calls **`register_key`** so wrong types are rejected and defaults apply on first run.

## One-time setup

Copy **`addons/savestate`** from the **repository root** into this folder so you have `minimal-demo/addons/savestate/` (including `save_manager.gd` and `plugin.cfg`). See `addons/README.txt`.

If Godot reports **`File not found`** for `res://addons/savestate/save_manager.gd` or disables the plugin with **“No directory found”**, the addon folder is missing or you opened a different project path — fix the copy, then **Project → Reload Current Project**.

## Run

1. **Project → Open** → this folder (`samples/minimal-demo`).
2. **Project Settings → Plugins** → enable **SaveState (Lite)**.
3. Press **F5**.

## What gets saved

| Key        | Type        | Notes                                      |
| ---------- | ----------- | ------------------------------------------ |
| `gold`     | int         | +10 Gold button                            |
| `player_x` / `player_y` | float | Square position                         |
| `xp`       | int         | +5 XP button                               |
| `accent`   | Color       | Cycle color — try editing in Save Browser Data tab |
| `stash`    | Dictionary  | `herbs` / `potions` counts                 |

### New file without overwriting `slot_0`

Use **`SaveManager.export_current_to_slot(&"slot_2")`** (or any file base: `checkpoint_boss`, … — becomes `checkpoint_boss.bin`). That writes the extra file **and** merges current KV + `__saveables` snapshots. **`slot_0`** on disk stays as-is until you press **Save (slot_0)** again.

To pull that snapshot back: **`SaveManager.import_slot_into_runtime(&"slot_2")`** (**Load from named slot** in the demo, with the same name in the line edit).

The Save Browser lists only real save slots (`.bin` / `.json`); it does **not** list **`.savestate_editor_hints.json`** (that file only stores Data-tab color hints for the editor).

### Thumbnails (`slot_N.jpg`)

**SaveState Pro** can grab the main viewport and save **`slot_0.jpg`** whenever you call **`persist()`**, **`persist_including_saveables()`**, **`persist_async()`**, or **`export_current_to_slot`** (writes **`slot_1.jpg`** for `slot_1`, etc.). **Lite-only** projects do not include this (no viewport capture in `save_manager.gd`).

## Save / load pattern

**Save** (see `_on_save_pressed` in `main.gd` — writes every key then `persist()`):

```gdscript
SaveManager.set_value(&"gold", player.gold)
SaveManager.set_value(&"stash", _stash.duplicate(true))
SaveManager.persist()
```

**Save a second slot** (after setting values the same way):

```gdscript
SaveManager.export_current_to_slot(&"slot_1")
```

**Load** (clear cache so disk is read again, then read keys):

```gdscript
SaveManager.clear_kv_cache()
player.gold = int(SaveManager.get_value(&"gold", 0))
```

`main.gd` connects **`migration_required`** so you can see the hook when you bump `savestate/current_version` and load an older file.

## SaveState Pro

**Lite** is required. **Pro** is optional if you copied `addons/savestate_pro` for local testing (async save, encryption, Save Browser extras). See the main [README](../../README.md) and [itch.io](https://chuumberry.itch.io/savestate-pro).
