@tool
class_name SaveStateGenerationStore
extends RefCounted
## Immutable files are authoritative. index.cache is optional and never selects a load.

const READER = preload("res://addons/savestate/encrypted_save_reader.gd")
const MAX_FILES := 4096


static func valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64 or value.ends_with("."):
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return value not in ["con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]


static func directory(root: String, slot: String) -> String:
	return root.path_join("generations").path_join(slot)


static func scan(root: String, slot: String) -> Dictionary:
	if not valid_id(slot):
		return {"error": ERR_INVALID_PARAMETER, "files": []}
	var folder := directory(root, slot)
	if not DirAccess.dir_exists_absolute(folder):
		return {"error": _directory_status(folder), "files": []}
	var dir := DirAccess.open(folder)
	if dir == null:
		return {"error": DirAccess.get_open_error(), "files": []}
	var files: Array[Dictionary] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".ssv"):
			var identity := parse_name(name)
			# Unknown finalized names cannot be silently ignored as an empty slot.
			if identity.is_empty() or files.size() >= MAX_FILES:
				dir.list_dir_end()
				return {"error": ERR_FILE_CORRUPT, "files": []}
			identity["path"] = folder.path_join(name)
			files.append(identity)
		name = dir.get_next()
	dir.list_dir_end()
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["sequence"] > b["sequence"])
	for index in range(1, files.size()):
		if files[index]["sequence"] == files[index - 1]["sequence"]:
			return {"error": ERR_FILE_CORRUPT, "files": []}
	return {"error": OK, "files": files}


static func parse_name(name: String) -> Dictionary:
	var parts := name.trim_suffix(".ssv").split("_")
	if parts.size() != 2 or parts[0].length() != 19 or parts[1].length() != 32 \
			or not parts[0].is_valid_int() or not SaveStateGenerationCodec._hex(parts[1]):
		return {}
	var sequence := int(parts[0])
	if sequence < 1 or "%019d" % sequence != parts[0]:
		return {}
	return {"sequence": sequence, "id": parts[1]}


static func read(path: String, keys: Dictionary = {}) -> SaveStateResult:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveStateResult.outcome(&"not_found" if not FileAccess.file_exists(path) else &"storage_unavailable", FileAccess.get_open_error(), "The generation could not be opened.")
	var length := file.get_length()
	if length > SaveStateGenerationCodec.MAX_BYTES + 256:
		file.close()
		return SaveStateResult.outcome(&"corrupt", ERR_FILE_CORRUPT, "The generation exceeds its size limit.")
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	if error != OK or bytes.size() != length:
		return SaveStateResult.outcome(&"storage_unavailable", ERR_FILE_CANT_READ, "The generation could not be read completely.")
	var result := decode(bytes, keys)
	result.path = path
	if result.ok:
		var identity := parse_name(path.get_file())
		if identity.is_empty() or identity["id"] != result.generation_id or identity["sequence"] != result.sequence:
			return SaveStateResult.outcome(&"corrupt", ERR_FILE_CORRUPT, "The generation filename disagrees with its content.")
	return result


static func decode(raw: PackedByteArray, keys: Dictionary = {}) -> SaveStateResult:
	var bytes := raw
	var header := SaveFormat.parse_header(raw)
	if int(header.get("error", ERR_FILE_CORRUPT)) == OK and int(header["format_version"]) == 2:
		if keys.get("aes", PackedByteArray()).size() != 32 or keys.get("hmac", PackedByteArray()).is_empty():
			return SaveStateResult.outcome(&"key_unavailable", ERR_UNCONFIGURED, "The original encryption keys are required.")
		var opened := READER.open_outer_save_file(raw, keys["aes"], keys["hmac"])
		if int(opened["error"]) != OK:
			return SaveStateResult.outcome(&"authentication_failed", ERR_INVALID_DATA, "The generation could not be authenticated. Check the keys and file.")
		bytes = opened["inner"]
	var decoded := SaveStateGenerationCodec.decode(bytes)
	if int(decoded["error"]) != OK:
		return SaveStateResult.outcome(&"unsupported_format" if int(decoded["error"]) == ERR_FILE_UNRECOGNIZED else &"corrupt", int(decoded["error"]) as Error, "The generation container is invalid.")
	var doc: Dictionary = decoded["document"]
	if not (doc.get("data") is Dictionary) or not (doc.get("schema") is int) or doc["schema"] < 1 \
			or not (doc.get("generation") is Dictionary) or not (doc.get("thumbnail") is PackedByteArray) \
			or doc["thumbnail"].size() > SaveStateGenerationCodec.MAX_THUMBNAIL:
		return SaveStateResult.outcome(&"corrupt", ERR_FILE_CORRUPT, "The generation document is invalid.")
	var meta: Dictionary = doc["generation"]
	if not (meta.get("id") is String) or meta["id"].length() != 32 or not SaveStateGenerationCodec._hex(meta["id"]) \
			or not (meta.get("sequence") is int) or meta["sequence"] < 1 or not (meta.get("slot") is String) \
			or not valid_id(meta["slot"]) or not (meta.get("protected") is bool) \
			or not (meta.get("created_unix") is int) or not (meta.get("source") is String):
		return SaveStateResult.outcome(&"corrupt", ERR_FILE_CORRUPT, "The generation identity is invalid.")
	var result := SaveStateResult.outcome(&"ok", OK)
	result.data = doc["data"]
	result.schema_version = doc["schema"]
	result.metadata = meta
	result.generation_id = meta["id"]
	result.sequence = meta["sequence"]
	result.slot_id = StringName(meta["slot"])
	result.thumbnail = doc["thumbnail"]
	return result


## Job contains owned bytes, paths, hashes and counts only. The hook is for failure/kill tests.
static func commit(job: Dictionary, hook: Callable = Callable()) -> SaveStateResult:
	AtomicWriter._mutex.lock()
	var result := _commit_locked(job, hook)
	AtomicWriter._mutex.unlock()
	return result


static func write_task(job: Dictionary, transfer: Dictionary) -> void:
	transfer["result"] = commit(job)


static func _stage(hook: Callable, name: String) -> Error:
	return int(hook.call(name)) as Error if hook.is_valid() else OK


static func _commit_locked(job: Dictionary, hook: Callable) -> SaveStateResult:
	var started := Time.get_ticks_usec()
	var path: String = job["path"]
	var partial := path.trim_suffix(".ssv") + ".partial"
	if _directory_status(path.get_base_dir()) != OK:
		return SaveStateResult.outcome(&"storage_unavailable", ERR_ALREADY_EXISTS, "A file occupies a required save directory. Choose another save root or move the obstructing file.")
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return SaveStateResult.outcome(&"storage_unavailable", error, "The generation directory could not be created.")
	if FileAccess.file_exists(path) or FileAccess.file_exists(partial):
		return SaveStateResult.outcome(&"conflict", ERR_ALREADY_EXISTS, "This generation already exists. Start a new save request.")
	var current := scan(job["root"], job["slot_id"])
	if int(current["error"]) != OK:
		return SaveStateResult.outcome(&"storage_unavailable", int(current["error"]) as Error, "The generation directory changed or could not be read.")
	if current["files"].size() >= MAX_FILES:
		return SaveStateResult.outcome(&"size_limit", ERR_OUT_OF_MEMORY, "This slot has reached the retained-file limit. Archive history before saving again.")
	if job.has("expected_latest"):
		var latest: String = "" if current["files"].is_empty() else str(current["files"][0]["id"])
		if latest != job["expected_latest"]:
			return SaveStateResult.outcome(&"conflict", ERR_BUSY, "The saved generation changed. Reload before applying this edit.")
	for prefix in ["source", "head"]:
		if job.has("expected_" + prefix + "_path") and FileAccess.get_sha256(job["expected_" + prefix + "_path"]) != job["expected_" + prefix + "_hash"]:
			return SaveStateResult.outcome(&"conflict", ERR_BUSY, "The inspected save changed. Reload it or save a copy.")
	error = _write_partial(partial, job["bytes"], hook)
	if error == OK: error = _stage(hook, "validate")
	if error == OK: error = AtomicWriter._verify_read_matches(partial, job["bytes"])
	if error == OK: error = _stage(hook, "finalize")
	if error == OK: error = DirAccess.rename_absolute(partial, path)
	if error != OK:
		# An incomplete candidate is never selected. Keep it for inspection, never touch prior generations.
		return SaveStateResult.outcome(&"storage_unavailable", error, "The generation was not committed. Earlier generations remain available.")
	# Commit point: a complete, previously validated byte buffer has its unique final name.
	var result := SaveStateResult.outcome(&"ok", OK, "Save committed.")
	result.path = path
	result.generation_id = job["generation_id"]
	result.sequence = job["sequence"]
	result.slot_id = job["slot_id"]
	if _stage(hook, "committed") != OK:
		result.warnings.append("The save committed; post-commit work was interrupted.")
		return result
	var candidates: Array = job.get("prune", [])
	var prune_error := _stage(hook, "prune")
	if prune_error == OK:
		for candidate in candidates:
			if FileAccess.get_sha256(candidate["path"]) == candidate["hash"]:
				if DirAccess.remove_absolute(candidate["path"]) != OK:
					prune_error = ERR_FILE_CANT_WRITE
	if prune_error != OK:
		result.warnings.append("Save committed. Some older generations could not be removed.")
	var index_error := _stage(hook, "index")
	if index_error == OK:
		var listing := scan(job["root"], job["slot_id"])
		var names: Array = []
		for item in listing["files"]:
			names.append({"id": item["id"], "sequence": str(item["sequence"])})
		index_error = AtomicWriter._write_locked(path.get_base_dir().path_join("index.cache"), JSON.stringify(names).to_utf8_buffer(), false, "")
	if index_error != OK:
		result.warnings.append("Save committed. The index will be rebuilt from generation files.")
	result.timings_usec["storage"] = Time.get_ticks_usec() - started
	return result


static func _write_partial(path: String, bytes: PackedByteArray, hook: Callable) -> Error:
	var error := _stage(hook, "open")
	if error != OK: return error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	error = _stage(hook, "write")
	if error == OK:
		file.store_buffer(bytes)
		error = file.get_error()
	if error == OK: error = _stage(hook, "flush")
	if error == OK:
		file.flush()
		error = file.get_error()
	# FileAccess.close() has no error return on the supported API baseline; readback follows close.
	file.close()
	return error


static func _directory_status(folder: String) -> Error:
	var ancestor := ProjectSettings.globalize_path(folder).simplify_path()
	while not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor): return ERR_ALREADY_EXISTS
		var parent := ancestor.get_base_dir()
		if parent == ancestor or parent.is_empty(): break
		ancestor = parent
	return OK
