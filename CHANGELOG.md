# Changelog

All notable changes to this project are documented here. Version numbers follow `addons/*/plugin.cfg` when you release.

## [1.0.0] - 2026-04-01

### Added

- **Lite:** `SaveManager` autoload, `AtomicWriter` (temp + rename), `SaveSlot`, sync slot API, KV `set_value` / `get_value` / `persist`, schema version in project settings, optional rolling `.bak` via `backup_on_commit` (default on).
- **Save Browser** editor dock (Lite): Explorer / Data / Config, preview, rename slot, health/verification hints.
- **Pro:** `pro_manager.gd` — async `persist_async`, `save_slot_async` / `load_slot_async`, optional AES-256 + HMAC, viewport thumbnail capture, Saveable inspector plugin, debugger plugin + Live Sync hook, Quick Setup tool menu.
- **Pro UX:** Lite dependency check (auto-enable Lite in project settings when possible), Pro-only UI gating in dock when Lite-only mirror.
- **Docs:** `QUICKSTART.md`, root `README` / `CHANGELOG` / `LICENSE`.
- **Lite standalone:** `savestate_saveable` collection uses duck typing (`get_storage_key` / `collect_snapshot` / `apply_snapshot`) so Lite compiles without the Pro `Saveable` class; Save Browser no longer preloads `pro_manager.gd`.

### Notes

- Bump `version` in `addons/savestate/plugin.cfg` and `addons/savestate_pro/plugin.cfg` when you tag a release so zips match the changelog.
