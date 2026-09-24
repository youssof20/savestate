@tool
class_name SaveStateGenerationSession
extends RefCounted
## Main-thread preparation and schema acceptance for runtime and editor generation APIs.

static var _sequences: Dictionary = {}


static func failure(error: Error, message: String) -> SaveStateResult:
	var code: StringName = &"invalid_data"
	match error:
		ERR_INVALID_PARAMETER: code = &"invalid_argument"
		ERR_BUSY: code = &"busy"
		ERR_UNCONFIGURED: code = &"key_unavailable"
		ERR_FILE_NOT_FOUND: code = &"not_found"
		ERR_OUT_OF_MEMORY: code = &"size_limit"
		ERR_FILE_CORRUPT: code = &"corrupt"
		ERR_ALREADY_EXISTS, ERR_FILE_CANT_OPEN, ERR_FILE_CANT_READ, ERR_CANT_OPEN, ERR_CANT_CREATE, ERR_UNAUTHORIZED:
			code = &"storage_unavailable"
	return SaveStateResult.outcome(code, error, message)


static func prepare(manager: Object, slot_id: StringName, data: Dictionary, thumbnail: PackedByteArray,
		options: Dictionary = {}) -> Dictionary:
	var job := {"generation_job": true, "slot_id": slot_id, "root": manager.save_root,
		"operation_id": SaveStateCoordinator.next_operation(), "revision": manager._runtime_revision,
		"epoch": manager._cache_epoch, "started": Time.get_ticks_usec()}
	job["result"] = failure(ERR_INVALID_PARAMETER, "Use a slot ID containing lowercase letters, numbers, hyphens, or underscores (up to 64 characters).")
	if not SaveStateGenerationStore.valid_id(str(slot_id)):
		return job
	var lease := SaveStateCoordinator.acquire(manager.save_root, manager.storage_owner_id() if manager.has_method("storage_owner_id") else manager.get_instance_id())
	if lease.is_empty():
		job["result"] = failure(ERR_BUSY, "Another manager has an operation queued for this save root.")
		return job
	job["lease"] = lease
	var config: Error = manager._validate_write_configuration()
	if config != OK:
		job["result"] = failure(config, "Enable encryption with valid original keys before saving.")
		return job
	var invalid: String = manager._validate_loaded_data(data)
	if not invalid.is_empty():
		job["result"] = failure(ERR_INVALID_DATA, "The data does not match the registered save schema.")
		job["result"].data_path = invalid
		return job
	var listing := SaveStateGenerationStore.scan(manager.save_root, str(slot_id))
	if int(listing["error"]) != OK:
		job["result"] = failure(int(listing["error"]) as Error, "The generation directory could not be read safely.")
		return job
	if listing["files"].size() >= SaveStateGenerationStore.MAX_FILES:
		job["result"] = failure(ERR_OUT_OF_MEMORY, "This slot has reached the retained-file limit. Archive history before saving again.")
		return job
	var key := lease + "/" + str(slot_id)
	var sequence: int = maxi(int(_sequences.get(key, 0)), 0 if listing["files"].is_empty() else int(listing["files"][0]["sequence"]))
	if sequence == 9223372036854775807:
		job["result"] = failure(ERR_OUT_OF_MEMORY, "The generation sequence is exhausted.")
		return job
	sequence += 1
	_sequences[key] = sequence
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	if id.length() != 32:
		job["result"] = failure(ERR_UNAVAILABLE, "A generation identity could not be created.")
		return job
	var warnings: PackedStringArray = []
	if thumbnail.size() > SaveStateGenerationCodec.MAX_THUMBNAIL:
		thumbnail = PackedByteArray()
		warnings.append("The thumbnail exceeded 256 KiB and was omitted.")
	var metadata := {"id": id, "sequence": sequence, "slot": str(slot_id),
		"created_unix": int(Time.get_unix_time_from_system()), "protected": bool(options.get("protected", false)),
		"source": str(options.get("source", ""))}
	if options.has("catalogue"):
		metadata["catalogue"] = options["catalogue"].duplicate(true)
	var encoded := SaveStateGenerationCodec.encode({"schema": manager.get_current_schema_version(),
		"data": data, "generation": metadata, "thumbnail": thumbnail})
	if int(encoded["error"]) != OK:
		job["result"] = failure(int(encoded["error"]) as Error, str(encoded.get("message", "The data cannot be encoded.")))
		job["result"].typed_path = encoded.get("typed_path", [])
		return job
	var bytes: PackedByteArray = manager._pre_write_transform(encoded["bytes"])
	var keys: Dictionary = manager._get_debug_crypto_keys().duplicate(true)
	var verified := SaveStateGenerationStore.decode(bytes, keys)
	if not verified.ok:
		job["result"] = verified
		return job
	var path := SaveStateGenerationStore.directory(manager.save_root, str(slot_id)).path_join("%019d_%s.ssv" % [sequence, id])
	job["worker"] = {"path": path, "root": str(manager.save_root), "slot_id": str(slot_id),
		"generation_id": id, "sequence": sequence, "bytes": bytes, "prune": []}
	if options.has("expected_latest"):
		job["worker"]["expected_latest"] = options["expected_latest"]
	job["keys"] = keys
	job["retention"] = maxi(2, int(manager.generation_retention))
	job["schema"] = manager.get_current_schema_version()
	job["source_generation"] = str(options.get("source", ""))
	job["result"] = verified
	job["result"].warnings = warnings
	job["result"].timings_usec["prepare"] = Time.get_ticks_usec() - int(job["started"])
	return job


static func refresh_prune(job: Dictionary) -> void:
	var listing := SaveStateGenerationStore.scan(job["root"], job["slot_id"])
	var eligible: Array = []
	var protected_sources: Array = []
	for file in listing["files"]:
		var protected := SaveStateGenerationStore.read(file["path"], job["keys"])
		if protected.ok and protected.metadata.get("protected", false): protected_sources.append(str(protected.metadata.get("source", "")))
	for file in listing["files"]:
		var candidate := SaveStateGenerationStore.read(file["path"], job["keys"])
		if candidate.ok and candidate.slot_id == job["slot_id"] and candidate.schema_version <= job["schema"] \
				and not candidate.metadata["protected"] and candidate.generation_id not in protected_sources and candidate.generation_id != job.get("source_generation", ""):
			eligible.append({"path": file["path"], "hash": FileAccess.get_sha256(file["path"])})
	# Keep at least one validated predecessor in addition to the new generation.
	job["worker"]["prune"] = eligible.slice(maxi(1, int(job["retention"]) - 1))


static func inspect(manager: Object, slot_id: StringName, recover: bool = false, generation: String = "") -> SaveStateResult:
	var listing := SaveStateGenerationStore.scan(manager.save_root, str(slot_id))
	if int(listing["error"]) != OK:
		return failure(int(listing["error"]) as Error, "The generation directory is invalid or unavailable.")
	if listing["files"].is_empty():
		return failure(ERR_FILE_NOT_FOUND, "No retained generation exists for this slot.")
	var first_failure: SaveStateResult
	var skipped := 0
	for file in listing["files"]:
		if not generation.is_empty() and file["id"] != generation:
			continue
		var result := SaveStateGenerationStore.read(file["path"], manager._get_debug_crypto_keys())
		if result.ok and result.slot_id != slot_id:
			result = failure(ERR_FILE_CORRUPT, "The generation belongs to a different slot.")
		if result.ok and result.schema_version > manager.get_current_schema_version():
			result = SaveStateResult.outcome(&"newer_schema", ERR_FILE_UNRECOGNIZED, "This save needs a newer game schema.")
		if result.ok:
			var migrated: SaveStateLoadResult = manager._run_schema_migration_pipeline(result.data, result.schema_version)
			if not migrated.ok:
				return migrated
			var invalid: String = manager._validate_loaded_data(migrated.data)
			if not invalid.is_empty():
				result = failure(ERR_INVALID_DATA, "The migrated data does not match the configured save schema.")
				result.data_path = invalid
				return result
			var validated := SaveStateGenerationCodec.encode({"data": migrated.data})
			if int(validated["error"]) != OK:
				result = failure(ERR_INVALID_DATA, "The migration produced unsupported save data.")
				result.typed_path = validated.get("typed_path", [])
				return result
			result.data = migrated.data
			if skipped > 0:
				result.status = &"recovered"
				result.recovered_from = result.generation_id
				result.warnings.append("Loaded an older generation; %d newer candidate(s) could not be validated." % skipped)
			return result
		if first_failure == null:
			first_failure = result
		# Keys, authentication, schema and I/O errors require an explicit decision, not a rollback.
		if not recover or not generation.is_empty() or result.status != &"corrupt":
			return result
		skipped += 1
	return first_failure if first_failure != null else failure(ERR_FILE_NOT_FOUND, "That generation was not found.")
