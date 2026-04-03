# Changelog

Single file for Lite + Pro. **Lite** changes ship from this repo and `savestate-lite-*.zip` on [GitHub Releases](https://github.com/youssof20/savestate/releases). **Pro** is paid and only on [itch.io](https://chuumberry.itch.io/savestate-pro) — every Pro section below points there.

## v1.2.0

### Lite

- typed KV: `register_key`, `unregister_key` — wrong `typeof` on `set_value` logs an error and skips the write; optional 4th arg `editor_value_hint` for Save Browser color UI
- debounced autosave: `mark_dirty()` + `auto_save_debounce_sec` + optional `dirty_persist_includes_saveables`
- declarative migrations: `set_schema_migrations` — ordered callables after defaults merge (index `i` = upgrade `i+1` → `i+2`)
- `export_save_file_to_json` / `export_slot_to_json` for human-readable dumps (same decode path as load)
- `SaveComponent` node — inspector list of parent property names for saveables
- `CollectionLink` — persistent “picked up” ids under KV `__savestate_collected_ids`
- `SaveStatePickupVacuum` — one manager removes nodes in a group already marked collected (same KV list as `CollectionLink` by default)
- template scene `addons/savestate/templates/save_menu_lite.tscn` (quick save/load `slot_0`)
- Save Browser Data tab: **ColorPicker** for keys tagged via `register_key` (`TYPE_COLOR`), `register_editor_hint`, or auto-detected r/g/b dict/array; hints in `save_root/.savestate_editor_hints.json`
- Save Browser dock polish: collapsible raw JSON/hex preview; icon toolbar + tooltips; Data **swatch** column and **click swatch** to edit color (popup); Commit/Discard/Pending grouped; Config sections + clearer encryption key status; **Re-detect** as a normal button; typography follows the editor theme (secondary text via alpha, not tiny fonts)
- `register_editor_hint`, `get_editor_hints_copy`
- `export_current_to_slot` / `import_slot_into_runtime` for multi-slot workflows
- `SaveStateUnixDisplay` (`addons/savestate/unix_display.gd`) — shared file-modified time labels (Save Browser + templates); documents `Time.get_datetime_string_from_unix_time` `use_space` parameter
- `plugin.cfg` compatibility note (Godot 4.3–4.6)
- Save Browser: Explorer omits **`.savestate_editor_hints.json`** (JSON sidecar for color hints, not a slot); refresh after Data **Commit** re-selects the same save file; Data tab pending diff avoids **`Color` vs `String`** inequality when editing via color picker; **Backup selected** copies the chosen main save to `.bak` (Lite + Pro) via **`create_backup_copy_for_file`**

### Pro

- [SaveState Pro on itch.io](https://chuumberry.itch.io/savestate-pro) — debounced flush uses `persist_async` instead of blocking `persist`; Save Browser **Export JSON** button (decrypts when keys are set, opens save folder)
- existing **Quick Setup / Saveable** inspector remains the visual “checkbox” path vs Lite’s typed property-name list
- **`templates/save_menu_pro.tscn`**: scrollable `slot_1…N` list, timestamps, optional `slot_N.jpg` thumbs, Load/Save/Delete + confirm; backdrop blocks clicks; uses `SaveStateUnixDisplay` for timestamps
- Pro plugin: detect Lite with `FileAccess.file_exists` (not `ResourceLoader.exists` on `plugin.cfg`, which is never a loadable resource); AcceptDialogs use `exclusive = false` so enabling Pro from Project Settings does not fight the Plugins panel modal
- **`pro_manager`**: viewport JPEG again on **`persist()`** / **`persist_including_saveables()`** (not only `persist_async`); **`export_current_to_slot`** writes **`slot_N.jpg`** beside the chosen slot

## v1.1.2

### Lite

- sample `samples/minimal-demo/` no longer copies the whole addon; copy `addons/savestate` from the repo or from the Lite zip before opening the project
- `addons/README.txt` in the sample explains the one-time copy step
- readme and quickstart updated so GitHub Releases is the place for the Lite zip only

### Pro

- [SaveState Pro on itch.io](https://chuumberry.itch.io/savestate-pro) — repackage your itch zip with Lite **1.1.2** plus Pro; include README + QUICKSTART only (no changelog inside the zip; changelog stays on GitHub)

## v1.1.1

### Lite

- `save_manager.gd` no longer names Pro-only `SaveSecurity` at parse time (fixes pure Lite projects and the sample)
- added `addons/savestate/encrypted_save_reader.gd` so Save Browser can still inspect Pro-encrypted outer saves when keys exist (same crypto as Pro)

### Pro

- [SaveState Pro on itch.io](https://chuumberry.itch.io/savestate-pro) — ship a bundle built against Lite **1.1.1** so editor health / dock behavior matches the Lite fix above

## v1.1.0

### Lite

- `samples/minimal-demo/` starter scene (move, gold, save/load)
- `migration_required(old_schema, new_schema)` on `SaveManager` when a loaded file schema is older than project setting `savestate/current_version`
- docs split: `docs/API.md`, `docs/ARCHITECTURE.md`, `docs/MIGRATION.md`
- readme trimmed; links to quickstart and docs
- GitHub Action publishes `savestate-lite-<tag>.zip` on each Release

### Pro

- [SaveState Pro on itch.io](https://chuumberry.itch.io/savestate-pro) — async save/load, optional encryption, Saveable inspector, debugger hooks, Save Browser extras; requires Lite enabled first; bundle Lite + Pro for itch buyers

## v1.0.0

### Lite

- first public Lite: atomic saves, rolling `.bak`, schema merge, `SaveManager` autoload, Save Browser dock

### Pro

- [SaveState Pro on itch.io](https://chuumberry.itch.io/savestate-pro) — initial paid addon (async, crypto, Saveable, editor tooling); sold and updated only on itch, not in this repo
