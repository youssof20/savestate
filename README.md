# SaveState Lite

[![Hand-tested](https://img.shields.io/badge/Hand--tested-Godot%204.3%E2%80%934.6-success)](#godot-version-support)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Godot 4 addon: **atomic** save files, rolling **`.bak`** backups, **schema versioning** with forward merge, and one **`SaveManager`** autoload for key–value data and named slots — without building a custom format from scratch.

**Docs:** [Quick start](QUICKSTART.md) · [Full API](docs/API.md) · [Architecture & threading](docs/ARCHITECTURE.md) · [Migration (incl. `migration_required`)](docs/MIGRATION.md) · [Starter sample](samples/minimal-demo/README.md)

---

## Why this exists

Godot projects often start with ad-hoc `FileAccess` writes. That becomes painful fast: torn writes after crashes, no backup story, and no clean way to evolve save data when you add fields. SaveState Lite centralizes **atomic commits** (write to temp → validate → rename), **optional `.bak`**, and a **single schema number** with merge-from-defaults for older files.

**Technical challenges baked in:** careful ordering with temp files and rename for atomicity; keeping async Pro saves safe by **snapshotting on the main thread** before `WorkerThreadPool` I/O (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)); and editor/plugin ordering so Lite loads before Pro when both are enabled.

See [CHANGELOG.md](CHANGELOG.md) — each version lists **Lite** (this repo) and **Pro** ([itch.io](https://chuumberry.itch.io/savestate-pro)) separately.

---

## Installation

1. Copy the `addons/savestate/` folder into your Godot project (merge with `addons/`).
2. **Project → Project Settings → Plugins** → enable **SaveState (Lite)**.
3. The **SaveManager** autoload is registered (`res://addons/savestate/save_manager.gd`).

**SaveState Pro** (paid, separate from this repo) requires both Lite and the Pro plugin folder in your project. See [itch.io](https://chuumberry.itch.io/savestate-pro).

**GitHub Releases** attach **`savestate-lite-<tag>.zip`** (drop-in `addons/savestate/`). Pushing a new tag `v*` triggers Actions to open the release and upload the zip. To **create or refresh** releases for existing tags (notes + zip), run **`tools/publish_github_releases.ps1`** from the repo root with **`GITHUB_TOKEN`** set to a PAT with repo **Contents** read/write (see the script header).

---

## Quick start

```gdscript
SaveManager.set_value(&"player_gold", 250)
SaveManager.persist()
```

```gdscript
var player_gold := int(SaveManager.get_value(&"player_gold", 0))
```

```gdscript
SaveManager.save_to_slot_sync(&"slot_1", {"player_health": 100})
var data := SaveManager.load_from_slot_sync(&"slot_1")
```

More patterns: **[QUICKSTART.md](QUICKSTART.md)**. Full method list: **[docs/API.md](docs/API.md)**.

---

## Saving nodes (Lite)

Lite does not ship a `Saveable` node in this repo. Nodes in group `savestate_saveable` that implement **`get_storage_key`**, **`collect_snapshot`**, and **`apply_snapshot`** participate in `persist_including_saveables()` / `load_from_slot_and_apply_saveables()`. The **Saveable** node and inspector tooling ship with **SaveState Pro**: [SaveState Pro on itch.io](https://chuumberry.itch.io/savestate-pro).

---

## Pro version

Pro swaps the autoload for `pro_manager.gd`, adds async save/load, optional AES-256 + HMAC, thumbnails, **Save Browser** dock extras, Saveable inspector, and Quick Setup menu entries. Details: [https://chuumberry.itch.io/savestate-pro](https://chuumberry.itch.io/savestate-pro)

---

## Godot version support

Godot **4.3**, **4.4**, **4.5**, **4.6** tested and supported.

---

## License

Lite is MIT licensed. Use it in any project, commercial or otherwise, with no attribution required.
