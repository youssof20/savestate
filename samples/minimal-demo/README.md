# SaveState — minimal starter sample

Self-contained Godot **4.3+** project: blue square moves with arrow keys, **Gold** increases with **+10 Gold**, **Save** / **Load** use the key–value `slot_0` store.

## Run

1. In Godot: **Project → Open**, choose this folder (`samples/minimal-demo`).
2. Enable **SaveState (Lite)** in **Project Settings → Plugins** if prompted.
3. Press **F5**.

## The “three lines” save/load

**Save**

```gdscript
SaveManager.set_value(&"gold", player.gold)
SaveManager.persist()
```

**Load**

```gdscript
SaveManager.clear_kv_cache()
player.gold = int(SaveManager.get_value(&"gold", 0))
```

`main.gd` also connects **`migration_required`** so you can see the hook when you bump `savestate/current_version` and load an older file.

## Updating the bundled addon

This folder includes a **copy** of `addons/savestate/` from the repo. After pulling Lite changes, re-copy from the repo root:

`addons/savestate/` → `samples/minimal-demo/addons/savestate/`

## SaveState Pro

This sample uses **Lite only**. Pro needs both `addons/savestate/` and `addons/savestate_pro/` in the same project; see the main [README](../../README.md).
