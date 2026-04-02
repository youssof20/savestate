# Changelog

## 1.1.2

- **Sample:** `samples/minimal-demo/` no longer duplicates Lite; copy `addons/savestate` from the repo root (or from `savestate-lite-*.zip`). See `samples/minimal-demo/addons/README.txt`.

## 1.1.1

- **Lite:** `save_manager.gd` no longer references Pro-only `SaveSecurity`. Encrypted-save inspection for the Save Browser uses `addons/savestate/encrypted_save_reader.gd`, so pure Lite projects (including `samples/minimal-demo/`) compile again.

## 1.1.0

- **Starter sample:** `samples/minimal-demo/` — small Godot project (move, gold, Save/Load). Open that folder as a project to try the addon.
- **`migration_required` signal:** emitted when a loaded save file’s schema is older than `savestate/current_version`, so you can run custom migration logic in Lite.
- **Docs:** API moved to `docs/API.md`; architecture and threading notes in `docs/ARCHITECTURE.md`; migration notes in `docs/MIGRATION.md`.
- **README:** shorter landing page with links to the docs and sample.

## 1.0.0

- Initial SaveState Lite public release: atomic saves, backups, schema merge, `SaveManager` autoload, Save Browser dock.
