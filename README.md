# SaveState for Godot 4

A save system that keeps your players' progress safe: **writes are atomic** (no half-written files if the game crashes), you get **automatic `.bak` backups** by default, and you can grow your game without breaking old saves thanks to **schema versioning**.

Two pieces work together:

- **SaveState (Lite)** — free core: `SaveManager`, slots, and a **Save Browser** panel right inside the Godot editor.
- **SaveState Pro** — paid add-on: async saves, optional encryption, thumbnails, and extra editor tools. Pro always needs Lite installed and enabled.

**Made by [chuumberry](https://itch.io/profile/chuumberry)** · Godot **4.3+** (tested on **4.6**)

**Source:** [github.com/youssof20/savestate](https://github.com/youssof20/savestate) — MIT, see [`LICENSE`](LICENSE). **`addons/savestate_pro/`** is gitignored here so it is not pushed to that remote; **Pro** is sold separately: **[SaveState Pro on itch.io](https://chuumberry.itch.io/savestate-pro)**.

---

## Choose your path

### I only need Lite

1. Add the `addons/savestate/` folder to your project.
2. Open **Project → Project Settings → Plugins** and turn on **SaveState (Lite)**.
3. Use the code below to save and load. Open the **Save Browser** dock in the editor to inspect files on disk.

### I have Pro (or I'm buying it)

1. Add **both** `addons/savestate/` and `addons/savestate_pro/`.
2. In Plugins, enable **SaveState (Lite)** first, then **SaveState Pro**.
3. If the editor asks you to restart, do it — that makes sure Lite loads before Pro.

Get **SaveState Pro** here: **[chuumberry.itch.io/savestate-pro](https://chuumberry.itch.io/savestate-pro)**.

---

## Code you'll actually use

Your autoload is called **`SaveManager`**.

**Simple key-value (great for coins, flags, stats):**

```gdscript
SaveManager.set_value(&"gold", 420)
print(SaveManager.get_value(&"gold", 0))
SaveManager.persist()   # writes to disk
```

**Named save slots (whole dictionaries per slot):**

```gdscript
SaveManager.save_to_slot_sync(&"slot_1", {"level": 3, "name": "Asha"})
var data = SaveManager.load_from_slot_sync(&"slot_1")
```

**Pro:** you can use async helpers like `persist_async()` so heavy saves don't hitch the frame — see `addons/savestate_pro/pro_manager.gd` after Pro is enabled.

---

## More help in this repo

| File | What it's for |
|------|---------------|
| [QUICKSTART.md](QUICKSTART.md) | Step-by-step: dock, Config tab, Pro extras |

**Releases:** each [GitHub Release](https://github.com/youssof20/savestate/releases) includes a **`savestate-lite-<tag>.zip`** you can unzip into your project (contains `addons/savestate/`). For smaller day-to-day changes, use [commits](https://github.com/youssof20/savestate/commits/main/) on `main`.

Enjoy the saves.
