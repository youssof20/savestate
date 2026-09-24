@tool
class_name SaveStateEditorStore
extends RefCounted
## Editor reads use runtime catalogues; writes append through the shared generation writer.
var manager: SaveManagerBase

func _init(owner: SaveManagerBase) -> void:
	manager = owner

func profile_root(profile: String) -> String:
	return SaveStateCatalogue.profile_root(manager.save_root, profile)

func history(profile: String, slot: String) -> SaveStateResult:
	if not SaveStateGenerationStore.valid_id(profile) or not SaveStateGenerationStore.valid_id(slot): return fail("invalid_argument", "Select a valid profile and save.")
	var listing := SaveStateGenerationStore.scan(profile_root(profile), slot)
	if listing.error != OK: return SaveStateGenerationSession.failure(listing.error, "The history directory cannot be read.")
	var entries: Array = []
	for file in listing.files:
		var candidate := SaveStateGenerationStore.read(file.path, manager._get_debug_crypto_keys())
		entries.append({"id": file.id, "sequence": file.sequence, "path": file.path, "status": str(candidate.status), "schema": candidate.schema_version,
			"created": candidate.metadata.get("created_unix", 0), "message": candidate.message})
	var result := SaveStateResult.outcome(&"ok", OK)
	result.data = {"entries": entries}
	return result

func read(profile: String, slot: String, generation: String = "") -> SaveStateResult:
	var listing := history(profile, slot)
	if not listing.ok: return listing
	for file in listing.data.entries:
		if generation != "" and file.id != generation: continue
		var result := SaveStateGenerationStore.read(file.path, manager._get_debug_crypto_keys())
		if not result.ok: return result
		if result.slot_id != StringName(slot) or not SaveStateCatalogue.valid_entry(result.metadata.get("catalogue"), false): return fail("corrupt", "The generation has invalid catalogue metadata.")
		if result.metadata.catalogue.profile != profile: return fail("corrupt", "The generation belongs to another profile.")
		result.profile_id = StringName(profile)
		result.path = file.path
		result.metadata["editor_hash"] = FileAccess.get_sha256(file.path)
		result.metadata["editor_head"] = listing.data.entries[0].id
		result.metadata["editor_head_path"] = listing.data.entries[0].path
		result.metadata["editor_head_hash"] = FileAccess.get_sha256(listing.data.entries[0].path)
		return result
	return fail("not_found", "No committed save exists. Run the game and save once.")

func preview(source: SaveStateResult) -> SaveStateResult:
	if not manager.supports_profiles(): return fail("unsupported_capability", "Migration previews require Pro. Runtime migrations are available in Lite.")
	if not source.ok: return source
	if FileAccess.get_sha256(source.path) != source.metadata.get("editor_hash", ""): return fail("conflict", "The source changed. Reload it before previewing.")
	var isolated: SaveManagerBase = manager.get_script().new()
	isolated._schema_migrations = manager._schema_migrations.duplicate()
	isolated._kv_types = manager._kv_types.duplicate()
	isolated._kv_registered_defaults = manager._kv_registered_defaults.duplicate(true)
	var migrated := isolated._run_schema_migration_pipeline(source.data.duplicate(true), source.schema_version)
	isolated.free()
	if not migrated.ok: return migrated
	var invalid := manager._validate_loaded_data(migrated.data)
	var encoded := SaveStateGenerationCodec.encode(migrated.data)
	if invalid != "" or encoded.error != OK: return fail("invalid_data", "Migration output contains unsupported values: " + invalid)
	var result := SaveStateResult.outcome(&"ok", OK, "Preview only. Source bytes are unchanged.")
	result.data = migrated.data
	result.metadata = {"changes": SaveStateEditSession.diff(source.data, result.data), "source_schema": source.schema_version, "target_schema": manager.get_current_schema_version()}
	return result

func write(source: SaveStateResult, data: Dictionary, action: String = "edit", label: String = "") -> SaveStateResult:
	if not manager.supports_profiles(): return fail("unsupported_capability", "The Lite editor is read-only. Use the runtime save API to write game state.")
	if not source.ok: return source
	if Engine.is_editor_hint() and EditorInterface.is_playing_scene(): return fail("busy", "Stop the game before writing disk saves. Live edits change game memory separately.")
	if manager._has_pending_writes() or manager._load_active: return fail("busy", "Wait for the current operation to finish.")
	if action not in ["edit", "branch", "recover", "rename", "delete", "migrate"]: return fail("invalid_argument", "Unknown editor operation.")
	if source.schema_version != manager.get_current_schema_version() and action != "migrate": return fail("schema_mismatch", "Preview the schema migration before writing this save.")
	if action in ["branch", "rename"] and not SaveStateCatalogue.label_valid(label): return fail("invalid_argument", "Use a nonempty name of up to 80 characters.")
	if FileAccess.get_sha256(source.path) != source.metadata.get("editor_hash", ""): return fail("conflict", "This generation changed. Reload it or save your edits as a copy from a verified source.")
	if action == "edit" and source.generation_id != source.metadata.editor_head: return fail("history_read_only", "History is read-only. Use Save as copy or Restore generation.")
	var root_lease := SaveStateCoordinator.acquire(manager.save_root, manager.get_instance_id())
	if root_lease.is_empty(): return fail("busy", "Another operation owns this save folder.")
	if action == "delete":
		var descriptor_context := SaveStateStorageContext.new(manager, manager.save_root.path_join(".profiles"), true)
		var descriptor := SaveStateGenerationSession.inspect(descriptor_context, source.profile_id)
		if not descriptor.ok or str(descriptor.data.get("active_slot", "")) == str(source.slot_id):
			SaveStateCoordinator.release(root_lease)
			return fail("active_context", "Load another playthrough in this profile before deleting its active save.")
	var context := SaveStateStorageContext.new(manager, profile_root(str(source.profile_id)))
	var id := source.slot_id
	var metadata: Dictionary = source.metadata.catalogue.duplicate(true)
	if action == "branch":
		var listing := SaveStateCatalogue.scan(manager, context.save_root)
		if not listing.ok or listing.data.entries.size() >= SaveStateCatalogue.MAX_SLOTS:
			SaveStateCoordinator.release(root_lease)
			return fail("size_limit", "The profile cannot accept another save.")
		id = StringName(Crypto.new().generate_random_bytes(16).hex_encode())
		metadata.alias = str(id)
		metadata.created_unix = int(Time.get_unix_time_from_system())
	if action in ["rename", "branch"]: metadata.display_name = label.strip_edges()
	metadata.deleted = action == "delete"
	metadata.saved_unix = int(Time.get_unix_time_from_system())
	metadata.save_kind = "editor"
	var options := {"catalogue": metadata, "source": source.generation_id, "protected": action == "migrate"}
	if action != "branch": options.expected_latest = source.metadata.editor_head
	var job := SaveStateGenerationSession.prepare(context, id, data, source.thumbnail, options)
	var result: SaveStateResult = job.result
	if result.ok:
		job.worker.expected_source_path = source.path
		job.worker.expected_source_hash = source.metadata.editor_hash
		if action != "branch":
			job.worker.expected_head_path = source.metadata.editor_head_path
			job.worker.expected_head_hash = source.metadata.editor_head_hash
		SaveStateGenerationSession.refresh_prune(job)
		result = SaveStateGenerationStore.commit(job.worker)
		result.metadata = job.result.metadata
		result.timings_usec.merge(job.result.timings_usec)
	SaveStateCoordinator.release(str(job.get("lease", "")))
	SaveStateCoordinator.release(root_lease)
	result.profile_id = source.profile_id
	result.slot_id = id
	return result

static func fail(status: String, message: String) -> SaveStateResult:
	return SaveStateResult.outcome(StringName(status), ERR_INVALID_DATA, message)
