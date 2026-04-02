# How SaveState works

## Atomic commits (all builds)

Each save writes the full file to a **temporary path** (often `*.tmp`), validates the bytes, then **renames** into the final filename. If the process or OS stops mid-write, you do not get a half-old, half-new file: the previous committed file stays valid until the new one replaces it.

When `backup_on_commit` is true (default), the previous main file is renamed to `.bak` before the new data lands, so you can recover from bad writes or manual edits.

## Thread safety (SaveState Pro)

**Concern:** If saving runs on a worker thread while the game keeps simulating, can the written file mix old and new state?

**Answer:** No — async saves use an explicit **snapshot phase on the main thread** before any worker runs.

1. **`persist_async`** (main thread): hydrates KV if needed, optionally captures a viewport thumbnail, builds `data` as `_kv_data.duplicate(true)` plus `gather_saveable_snapshots()` under `__saveables` when enabled.
2. **`save_slot_async`** (main thread): `var snapshot := data.duplicate(true)` — deep copy of the payload that will be serialized.
3. **Worker thread:** Only `_thread_save_impl` runs there, serializing and writing `snapshot` bytes. Mutations to the live scene or KV map after the snapshot do not affect that write.

Loads that use `WorkerThreadPool` read raw bytes on the worker, then **`call_deferred`** back to the main thread to parse and apply — parsing does not run concurrently with your gameplay scripts.

## Schema and migration (Lite)

Embedded `schema_version` in each file is compared to Project Settings `savestate/current_version`. Older files are merged with defaults from `set_default_state_for_migration()` where applicable, and **`migration_required`** is emitted so you can run custom fix-up code without Pro. See [MIGRATION.md](MIGRATION.md).

## Godot threading notes

Godot 4’s `WorkerThreadPool` is used for bounded parallel tasks; SaveState Pro does not spin ad-hoc `Thread` instances per save. The snapshot boundary is what keeps save data deterministic relative to the frame where you requested the save.
