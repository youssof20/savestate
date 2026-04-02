# Quick start - SaveState (Lite) + Pro

## 1. Install

- **Lite only:** copy `addons/savestate/` into your project.
- **Pro:** copy **both** `addons/savestate/` and `addons/savestate_pro/`.

## 2. Enable plugins

**Project → Project Settings → Plugins**

1. Enable **SaveState (Lite)** first (provides the Save Browser dock and autoload registration).
2. Enable **SaveState Pro** second if you bought Pro.

If Pro was enabled first, the Pro plugin may add Lite to your enabled list automatically — **restart the editor** when prompted so Lite loads.

## 3. Save Browser (editor)

After Lite loads, open the **Save Browser** dock (tab name may vary).

- **Explorer** — lists saves under `SaveManager.save_root`
- **Data** — edit decoded payload (commit and Live Sync need Pro)
- **Config** — JSON vs binary, backup toggle; Pro adds encryption key generation

## 4. Pro-only workflow (optional)

- **Config:** generate AES/HMAC keys when you want encrypted saves.
- **Inspector:** select a `Saveable` node, then use the property picker and optional `savestate_*` metadata on the parent.
- **Tools:** **SaveState Pro → Quick Setup: Add Saveable to selection**

## 5. Minimal runtime example

```gdscript
SaveManager.set_value(&"gold", 420)
SaveManager.persist()

# Pro: use persist_async() from pro_manager.gd (connect to signals as needed)
```

Use `save_to_slot_sync` / `load_from_slot_sync` for named slots (see `addons/savestate/save_manager.gd`).
