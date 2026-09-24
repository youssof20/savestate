@tool
class_name SaveStateCatalogue
extends RefCounted
## Generation metadata is authoritative. The encrypted-capable cache contains no gameplay payload.

const MAX_SLOTS := 128
const MAX_PROFILES := 64


static func label_valid(label: String) -> bool:
	if label.strip_edges().is_empty() or label.length() > 80:
		return false
	for character in label:
		if character.unicode_at(0) < 32: return false
	return true


static func profile_root(root: String, profile: String) -> String:
	return root.path_join("profiles").path_join(profile)


static func scan(manager: Node, root: String, profiles: bool = false, refresh: bool = false) -> SaveStateResult:
	var directory := root.path_join("generations")
	var available := SaveStateGenerationStore._directory_status(directory)
	if available != OK:
		return SaveStateGenerationSession.failure(available, "The catalogue directory is unavailable.")
	var ids := PackedStringArray()
	if DirAccess.dir_exists_absolute(directory):
		var dir := DirAccess.open(directory)
		if dir == null: return SaveStateGenerationSession.failure(DirAccess.get_open_error(), "The catalogue cannot be opened.")
		ids = dir.get_directories()
	if ids.size() > (MAX_PROFILES if profiles else MAX_SLOTS):
		return SaveStateGenerationSession.failure(ERR_OUT_OF_MEMORY, "The catalogue has too many entries.")
	var cache_path := root.path_join("catalogue.cache")
	var cached := {}
	var cache_encrypted := false
	var private_entries := false
	if not refresh and FileAccess.file_exists(cache_path):
		var read := SaveManagerBase._read_load_bytes(cache_path)
		if int(read["error"]) == OK and read["raw"].size() <= 1024 * 1024:
			cache_encrypted = SaveFormat.parse_header(read["raw"]).get("format_version", 0) == 2
			var bytes: PackedByteArray = manager._post_read_transform(read["raw"])
			var decoded := SaveStateGenerationCodec.decode(bytes)
			if int(decoded["error"]) == OK: cached = decoded["document"]
	var entries: Array = []
	var next_cache := {}
	for id in ids:
		if not SaveStateGenerationStore.valid_id(id):
			return SaveStateGenerationSession.failure(ERR_FILE_CORRUPT, "The catalogue contains an invalid storage ID.")
		var listing := SaveStateGenerationStore.scan(root, id)
		var entry := {"id": id, "status": "incomplete", "display_name": "Incomplete save", "deleted": false}
		if int(listing["error"]) != OK:
			entry["status"] = "corrupt"
		elif not listing["files"].is_empty():
			var file: Dictionary = listing["files"][0]
			var hash := FileAccess.get_sha256(file["path"])
			var previous: Variant = cached.get(id)
			var header_file := FileAccess.open(file["path"], FileAccess.READ)
			var encrypted := false
			if header_file != null:
				encrypted = SaveFormat.parse_header(header_file.get_buffer(SaveFormat.HEADER_SIZE)).get("format_version", 0) == 2
				header_file.close()
			private_entries = private_entries or encrypted
			if previous is Dictionary and previous.get("hash") == hash and previous.get("generation_id") == file["id"] \
					and (not encrypted or cache_encrypted) and previous.get("entry") is Dictionary:
				entry = previous["entry"].duplicate(true)
			else:
				var candidate := SaveStateGenerationStore.read(file["path"], manager._get_debug_crypto_keys())
				entry["status"] = str(candidate.status)
				if candidate.ok:
					var metadata: Variant = candidate.metadata.get("catalogue")
					if candidate.slot_id != StringName(id) or not valid_entry(metadata, profiles):
						entry["status"] = "corrupt"
					else:
						entry = metadata.duplicate(true)
						entry["id"] = id
						entry["status"] = "deleted" if entry["deleted"] else "ok"
						entry["schema_version"] = candidate.schema_version
						entry["thumbnail_available"] = not candidate.thumbnail.is_empty()
				entry["generation_id"] = file["id"]
				entry["sequence"] = file["sequence"]
			# A damaged head must not erase a known alias and allow accidental recreation.
			# Older authenticated metadata is routing information only; loading still fails.
			if entry.get("status") == "corrupt":
				for older in listing["files"].slice(1):
					var prior := SaveStateGenerationStore.read(older["path"], manager._get_debug_crypto_keys())
					if prior.ok and prior.slot_id == StringName(id) and valid_entry(prior.metadata.get("catalogue"), profiles):
						var damaged := entry.duplicate(true)
						entry = prior.metadata["catalogue"].duplicate(true)
						entry.merge(damaged, true)
						entry["display_name"] = prior.metadata["catalogue"]["display_name"]
						entry["recovery_generation_id"] = older["id"]
						break
			if entry.get("status") in ["ok", "deleted"]:
				next_cache[id] = {"entry": entry.duplicate(true), "hash": hash, "generation_id": file["id"]}
			if not profiles and int(entry.get("schema_version", 1)) > manager.get_current_schema_version():
				entry["status"] = "newer_schema"
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var comparison := str(a["display_name"]).naturalnocasecmp_to(str(b["display_name"]))
		return a["id"] < b["id"] if comparison == 0 else comparison < 0
	)
	var result := SaveStateResult.outcome(&"ok", OK)
	result.data = {"entries": entries}
	# Rebuilds are optional. A locked/missing key never causes a plaintext cache write.
	if not Engine.is_editor_hint() and manager._validate_write_configuration() == OK and not ids.is_empty():
		var encoded := SaveStateGenerationCodec.encode(next_cache)
		if int(encoded["error"]) == OK:
			var bytes: PackedByteArray = manager._pre_write_transform(encoded["bytes"])
			if private_entries and SaveFormat.parse_header(bytes).get("format_version", 0) != 2:
				return result
			if bytes.is_empty() or AtomicWriter.write_atomic(cache_path, bytes) != OK:
				result.warnings.append("The catalogue cache could not be updated; save files remain usable.")
	return result


static func valid_entry(value: Variant, profiles: bool) -> bool:
	if not (value is Dictionary) or not (value.get("display_name") is String) or not label_valid(value["display_name"]) \
			or not (value.get("deleted") is bool) or not (value.get("created_unix") is int):
		return false
	if profiles: return value.get("kind") == "profile"
	return value.get("kind") == "playthrough" and value.get("alias") is String \
		and SaveStateGenerationStore.valid_id(value["alias"]) and value.get("profile") is String \
		and SaveStateGenerationStore.valid_id(value["profile"]) and value.get("playtime_usec") is int \
		and value["playtime_usec"] >= 0 and value.get("saved_unix") is int
