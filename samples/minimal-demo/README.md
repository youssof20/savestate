# SaveState — minimal starter sample

Godot **4.3+** project: blue square moves with arrow keys, **Gold** with **+10 Gold**, **Save** / **Load** use the key–value `slot_0` store.

## One-time setup

Copy **`addons/savestate`** from the **repository root** into this folder so you have `minimal-demo/addons/savestate/`. See `addons/README.txt`.

## Run

1. **Project → Open** → this folder (`samples/minimal-demo`).
2. **Project Settings → Plugins** → enable **SaveState (Lite)**.
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

`main.gd` connects **`migration_required`** so you can see the hook when you bump `savestate/current_version` and load an older file.

## SaveState Pro

This sample targets **Lite** only. SaveState Pro is distributed separately; see the main [README](../../README.md) and [itch.io](https://chuumberry.itch.io/savestate-pro).
