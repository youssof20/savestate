@tool
class_name SaveStatePlaythroughSession
extends RefCounted
## Owns active context. Slot/profile descriptors are ordinary immutable generations.

var owner_ref: WeakRef
var enabled: bool = false
var active_profile: StringName = &"default"
var active_slot: StringName = &"main"
var epoch: int = 0
var root_path: String = ""
var _profile: SaveStateResult
var _slot_metadata: Dictionary = {}
var _entered_usec: int = 0
var _busy: bool = false
var _saved_revision: int = -1
var _pending_aliases: Dictionary = {}


func _init(manager: Node) -> void:
	owner_ref = weakref(manager)


func manager() -> Node:
	return owner_ref.get_ref()


func unavailable() -> SaveStateResult:
	return SaveStateGenerationSession.failure(ERR_BUSY, "Finish the current operation before changing playthroughs.")


func has_unsaved_changes() -> bool:
	return enabled and manager()._runtime_revision != _saved_revision


func _begin() -> String:
	var owner := manager()
	if SaveStateCoordinator.editor_game_running(): return ""
	if _busy or owner._has_pending_writes() or owner._load_active or owner._closing:
		return ""
	if enabled and root_path != owner.save_root:
		return ""
	var lease := SaveStateCoordinator.acquire(owner.save_root, owner.get_instance_id())
	_busy = not lease.is_empty()
	return lease


func _end(lease: String, result: SaveStateResult) -> SaveStateResult:
	SaveStateCoordinator.release(lease)
	_busy = false
	result.profile_id = active_profile
	return result


func _context(profile: StringName, descriptors: bool = false) -> SaveStateStorageContext:
	var owner := manager()
	return SaveStateStorageContext.new(owner, owner.save_root.path_join(".profiles") if descriptors else SaveStateCatalogue.profile_root(owner.save_root, str(profile)), descriptors)


func _write(context: SaveStateStorageContext, id: StringName, data: Dictionary, metadata: Dictionary, thumbnail: PackedByteArray = PackedByteArray(), source: String = "") -> SaveStateResult:
	var job := SaveStateGenerationSession.prepare(context, id, data, thumbnail, {"catalogue": metadata, "source": source})
	var result: SaveStateResult = job["result"]
	if result.ok:
		SaveStateGenerationSession.refresh_prune(job)
		result = SaveStateGenerationStore.commit(job["worker"])
		result.metadata = job["result"].metadata
		result.schema_version = job["schema"]
		result.warnings.append_array(job["result"].warnings)
	SaveStateCoordinator.release(str(job.get("lease", "")))
	return result


func _read_profile(id: StringName) -> SaveStateResult:
	var candidate := SaveStateGenerationSession.inspect(_context(id, true), id)
	if candidate.ok and (not SaveStateCatalogue.valid_entry(candidate.metadata.get("catalogue"), true) \
			or not (candidate.data.get("progression") is Dictionary) or not (candidate.data.get("active_slot") is String)):
		return SaveStateGenerationSession.failure(ERR_FILE_CORRUPT, "The profile descriptor is invalid.")
	if candidate.ok and candidate.metadata["catalogue"]["deleted"]:
		return SaveStateGenerationSession.failure(ERR_FILE_NOT_FOUND, "This profile was deleted.")
	return candidate


func _read_slot(profile: StringName, slot: StringName, recover: bool = false) -> SaveStateResult:
	var candidate := SaveStateGenerationSession.inspect(_context(profile), slot, recover)
	if candidate.ok and (not SaveStateCatalogue.valid_entry(candidate.metadata.get("catalogue"), false) \
			or candidate.metadata["catalogue"]["profile"] != str(profile)):
		return SaveStateGenerationSession.failure(ERR_FILE_CORRUPT, "The playthrough identity is invalid.")
	if candidate.ok and candidate.metadata["catalogue"]["deleted"]:
		return SaveStateGenerationSession.failure(ERR_FILE_NOT_FOUND, "This playthrough was deleted.")
	return candidate


func _selection(profile: SaveStateResult, slot: StringName) -> SaveStateResult:
	var data := profile.data.duplicate(true)
	data["active_slot"] = str(slot)
	var result := _write(_context(profile.slot_id, true), profile.slot_id, data, profile.metadata["catalogue"])
	if result.ok:
		profile.data = data
		profile.generation_id = result.generation_id
	return result


func _activate(profile: StringName, slot: StringName, descriptor: SaveStateResult, candidate: SaveStateResult) -> void:
	enabled = true
	root_path = manager().save_root
	active_profile = profile
	active_slot = slot
	_profile = descriptor
	_slot_metadata = candidate.metadata["catalogue"].duplicate(true)
	_entered_usec = Time.get_ticks_usec()
	epoch += 1
	var kv := candidate.data.duplicate(true)
	kv.erase("__saveables")
	kv.erase("__world")
	manager().replace_kv_data(kv)
	_saved_revision = manager()._runtime_revision


func start(allow_legacy: bool = false) -> SaveStateResult:
	if enabled:
		if root_path != manager().save_root: return unavailable()
		return SaveStateResult.outcome(&"ok", OK)
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	var owner := manager()
	var descriptor := _read_profile(&"default")
	if not allow_legacy and descriptor.status == &"not_found":
		for file in (DirAccess.get_files_at(owner.save_root) if DirAccess.dir_exists_absolute(owner.save_root) else PackedStringArray()):
			if file == ".savestate_editor_hints.json": continue
			if file.ends_with(".bin") or file.ends_with(".json"):
				return _end(lease, SaveStateResult.outcome(&"legacy_present", ERR_ALREADY_EXISTS, "Existing legacy saves were found. Import their data or explicitly start a separate playthrough."))
		if DirAccess.dir_exists_absolute(owner.save_root.path_join("generations")):
			return _end(lease, SaveStateResult.outcome(&"legacy_present", ERR_ALREADY_EXISTS, "Existing standalone generations were found. Import their data or explicitly start a separate playthrough."))
	if descriptor.status == &"not_found":
		# A deleted descriptor is still an existing profile, never a fresh installation.
		var existing := SaveStateGenerationStore.scan(owner.save_root.path_join(".profiles"), "default")
		if int(existing["error"]) != OK or not existing["files"].is_empty(): return _end(lease, descriptor)
		var meta := {"kind": "profile", "display_name": "Default", "created_unix": int(Time.get_unix_time_from_system()), "deleted": false}
		var written := _write(_context(&"default", true), &"default", {"progression": {}, "active_slot": ""}, meta)
		if not written.ok: return _end(lease, written)
		descriptor = _read_profile(&"default")
	if not descriptor.ok: return _end(lease, descriptor)
	var slot := StringName(descriptor.data["active_slot"])
	if slot == &"": slot = &"main"
	var candidate := _read_slot(&"default", slot)
	if candidate.status == &"not_found" and descriptor.data["active_slot"] == "":
		var existing := SaveStateGenerationStore.scan(_context(&"default").save_root, str(slot))
		if int(existing["error"]) != OK or not existing["files"].is_empty(): return _end(lease, candidate)
		var initial: Dictionary = owner._kv_data.duplicate(true) if owner._kv_hydrated else {}
		var written := _write(_context(&"default"), slot, initial, _new_metadata(&"default", "default", "Playthrough 1"))
		if not written.ok: return _end(lease, written)
		candidate = _read_slot(&"default", slot)
	if not candidate.ok: return _end(lease, candidate)
	var staged: SaveStateResult = manager()._stage_world_candidate(candidate.data)
	if not staged.ok: return _end(lease, staged)
	candidate.timings_usec.merge(staged.timings_usec)
	var selected := _selection(descriptor, slot)
	if not selected.ok:
		manager()._abort_world_restore()
		return _end(lease, selected)
	_activate(&"default", slot, descriptor, candidate)
	manager()._commit_world_restore()
	return _end(lease, candidate)


func _new_metadata(profile: StringName, alias: String, label: String) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	return {"kind": "playthrough", "profile": str(profile), "alias": alias, "display_name": label,
		"deleted": false, "created_unix": now, "saved_unix": now, "playtime_usec": 0,
		"scene_id": "", "location": "", "save_kind": "manual", "game_version": str(ProjectSettings.get_setting("application/config/version", "")), "container_version": 3}


func list_slots(include_deleted: bool = false, refresh: bool = false) -> SaveStateResult:
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	var result := SaveStateCatalogue.scan(manager(), _context(active_profile).save_root, false, refresh)
	if result.ok and not include_deleted:
		result.data["entries"] = result.data["entries"].filter(func(entry): return not entry.get("deleted", false))
	return _end(lease, result)


func _resolve(reference: StringName, include_deleted: bool = false) -> SaveStateResult:
	if reference == &"": reference = active_slot
	for pending in _pending_aliases.values():
		if pending["entry"]["id"] == str(reference) or pending["entry"]["alias"] == str(reference):
			var reserved := SaveStateResult.outcome(&"ok", OK)
			reserved.slot_id = StringName(pending["entry"]["id"])
			reserved.data = pending["entry"].duplicate(true)
			return reserved
	var listing := SaveStateCatalogue.scan(manager(), _context(active_profile).save_root)
	if not listing.ok: return listing
	if reference == &"": reference = active_slot
	var matches: Array = []
	for entry in listing.data["entries"]:
		if entry["id"] == str(reference) or entry.get("alias") == str(reference):
			matches.append(entry)
	if matches.size() > 1: return SaveStateGenerationSession.failure(ERR_FILE_CORRUPT, "Multiple playthroughs use this name. Select a unique internal ID.")
	if matches.is_empty(): return SaveStateGenerationSession.failure(ERR_FILE_NOT_FOUND, "No playthrough has that name or ID.")
	var entry: Dictionary = matches[0]
	if entry.get("deleted", false) and not include_deleted: return SaveStateResult.outcome(&"deleted", ERR_DOES_NOT_EXIST, "This playthrough was deleted. Use a different name for a new save.")
	var result := SaveStateResult.outcome(&"ok", OK)
	result.slot_id = StringName(entry["id"])
	result.data = entry
	return result


func prepare_save(reference: StringName, include_saveables: bool, asynchronous: bool = false, capture_thumbnail: bool = true) -> Dictionary:
	var owner := manager()
	if not enabled:
		var started := start()
		if not started.ok: return {"result": started}
	if SaveStateCoordinator.editor_game_running(): return {"result": unavailable()}
	if _busy or owner._load_active or owner._closing or root_path != owner.save_root \
			or (not asynchronous and owner._has_pending_writes()): return {"result": unavailable()}
	var lease := SaveStateCoordinator.acquire(root_path, owner.get_instance_id())
	if lease.is_empty(): return {"result": unavailable()}
	_busy = true
	var found := _resolve(reference)
	var id := found.slot_id
	var metadata := found.data.duplicate(true) if found.ok else {}
	if not found.ok:
		if found.status != &"not_found":
			return {"result": _end(lease, found)}
		if not SaveStateGenerationStore.valid_id(str(reference)):
			return {"result": _end(lease, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Use a save alias of up to 64 lowercase letters, digits, underscores, or hyphens."))}
		var listing := SaveStateCatalogue.scan(owner, _context(active_profile).save_root)
		if not listing.ok: return {"result": _end(lease, listing)}
		var reserved_ids := {}
		for entry in listing.data["entries"]: reserved_ids[entry["id"]] = true
		for pending in _pending_aliases.values(): reserved_ids[pending["entry"]["id"]] = true
		if reserved_ids.size() >= SaveStateCatalogue.MAX_SLOTS:
			return {"result": _end(lease, SaveStateGenerationSession.failure(ERR_OUT_OF_MEMORY, "The profile has reached its playthrough limit."))}
		id = StringName(Crypto.new().generate_random_bytes(16).hex_encode())
		metadata = _new_metadata(active_profile, str(reference), str(reference))
	elif found.data.get("status") != "ok":
		return {"result": _end(lease, SaveStateResult.outcome(StringName(found.data["status"]), ERR_FILE_CORRUPT, "The target playthrough must be inspected or recovered before saving over it."))}
	# Metadata supplied by listings includes cache-only fields. Authoritative fields are explicit below.
	for key in ["id", "status", "generation_id", "sequence", "schema_version", "thumbnail_available"]: metadata.erase(key)
	metadata["saved_unix"] = int(Time.get_unix_time_from_system())
	if id == active_slot:
		metadata["playtime_usec"] = int(_slot_metadata.get("playtime_usec", 0)) + maxi(0, Time.get_ticks_usec() - _entered_usec)
	metadata["save_kind"] = "autosave" if owner._auto_request else "manual"
	var identity := [owner.save_root, active_profile, active_slot, epoch]
	var data: Dictionary = owner._kv_data.duplicate(true)
	if include_saveables:
		owner.save_requested.emit()
		var identities: SaveStateResult = owner.validate_saveables()
		if not identities.ok: return {"result": _end(lease, identities)}
		data = owner._kv_data.duplicate(true)
		data["__saveables"] = owner.gather_saveable_snapshots()
	var captured_world: SaveStateResult = owner._capture_world_state()
	if not captured_world.ok: return {"result": _end(lease, captured_world)}
	if not captured_world.data.is_empty(): data["__world"] = captured_world.data
	if identity != [owner.save_root, active_profile, active_slot, epoch]:
		return {"result": _end(lease, unavailable())}
	var context := _context(active_profile)
	var thumbnail: PackedByteArray = owner._capture_thumbnail_bytes() if capture_thumbnail and owner.has_method("_capture_thumbnail_bytes") else PackedByteArray()
	var job := SaveStateGenerationSession.prepare(context, id, data, thumbnail, {"catalogue": metadata})
	job["result"].timings_usec.merge(captured_world.timings_usec)
	job["session_context"] = {"root": root_path, "profile": active_profile, "slot": active_slot, "epoch": epoch,
		"revision": owner._runtime_revision, "auto": owner._auto_request, "lease": lease}
	job["storage_context"] = context
	if job["result"].ok:
		var alias: String = metadata["alias"]
		if not _pending_aliases.has(alias):
			var entry := metadata.duplicate(true)
			entry["id"] = str(id)
			entry["status"] = "ok"
			_pending_aliases[alias] = {"count": 0, "entry": entry}
		_pending_aliases[alias]["count"] += 1
		job["pending_alias"] = alias
	_busy = false
	return job


func complete(job: Dictionary, result: SaveStateResult) -> void:
	var captured: Dictionary = job["session_context"]
	var owner := manager()
	var alias: String = job.get("pending_alias", "")
	if _pending_aliases.has(alias):
		_pending_aliases[alias]["count"] -= 1
		if _pending_aliases[alias]["count"] == 0: _pending_aliases.erase(alias)
	result.profile_id = captured["profile"]
	if result.ok:
		result.slot_id = job["slot_id"]
		if root_path == captured["root"] and owner.save_root == root_path and active_profile == captured["profile"] and epoch == captured["epoch"]:
			# Saving a named checkpoint does not switch the active playthrough.
			if job["slot_id"] == active_slot and captured["revision"] == owner._runtime_revision:
				_saved_revision = captured["revision"]
				_slot_metadata = job["result"].metadata["catalogue"].duplicate(true)
				_entered_usec = Time.get_ticks_usec()
				if captured["revision"] >= owner._dirty_revision:
					owner._dirty_pending = false
					owner._dirty_retries = 0
					if owner._dirty_timer != null: owner._dirty_timer.stop()
	SaveStateCoordinator.release(captured["lease"])
	owner._finish_dirty_job({"auto": captured["auto"]}, result.error)


func load_slot(reference: StringName, recover: bool = false, discard_unsaved: bool = false) -> SaveStateResult:
	if not enabled:
		var initialized := start()
		if not initialized.ok: return initialized
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	if has_unsaved_changes() and not discard_unsaved:
		return _end(lease, SaveStateResult.outcome(&"unsaved_changes", ERR_BUSY, "Save the current playthrough or explicitly discard its unsaved changes."))
	var found := _resolve(reference)
	if not found.ok: return _end(lease, found)
	var context := [manager().save_root, manager()._runtime_revision, manager()._migration_revision, manager().get_current_schema_version(), manager()._get_debug_crypto_keys()]
	var candidate := _read_slot(active_profile, found.slot_id, recover)
	if not candidate.ok: return _end(lease, candidate)
	if context != [manager().save_root, manager()._runtime_revision, manager()._migration_revision, manager().get_current_schema_version(), manager()._get_debug_crypto_keys()]:
		return _end(lease, unavailable())
	var descriptor := _read_profile(active_profile)
	if not descriptor.ok: return _end(lease, descriptor)
	var staged: SaveStateResult = manager()._stage_world_candidate(candidate.data)
	if not staged.ok: return _end(lease, staged)
	candidate.timings_usec.merge(staged.timings_usec)
	var selected := _selection(descriptor, found.slot_id)
	if not selected.ok:
		manager()._abort_world_restore()
		return _end(lease, selected)
	_activate(active_profile, found.slot_id, descriptor, candidate)
	manager()._commit_world_restore()
	manager().load_requested.emit()
	manager().apply_saveables_from_bundle(candidate.data.get("__saveables", {}))
	return _end(lease, candidate)


func new_playthrough(label: String, initial: Dictionary, discard_unsaved: bool = false) -> SaveStateResult:
	if not enabled:
		var initialized := start()
		if not initialized.ok: return initialized
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	if not SaveStateCatalogue.label_valid(label): return _end(lease, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Use a nonempty display name of up to 80 characters."))
	if has_unsaved_changes() and not discard_unsaved: return _end(lease, SaveStateResult.outcome(&"unsaved_changes", ERR_BUSY, "Save or explicitly discard the current changes first."))
	var listing := SaveStateCatalogue.scan(manager(), _context(active_profile).save_root)
	if not listing.ok: return _end(lease, listing)
	if listing.data["entries"].size() >= SaveStateCatalogue.MAX_SLOTS: return _end(lease, SaveStateGenerationSession.failure(ERR_OUT_OF_MEMORY, "The profile has reached its playthrough limit."))
	var staged: SaveStateResult = manager()._stage_world_candidate(initial)
	if not staged.ok: return _end(lease, staged)
	var id := StringName(Crypto.new().generate_random_bytes(16).hex_encode())
	var result := _write(_context(active_profile), id, initial, _new_metadata(active_profile, str(id), label))
	if result.ok:
		var candidate := _read_slot(active_profile, id)
		var descriptor := _read_profile(active_profile)
		var selected := _selection(descriptor, id) if descriptor.ok else descriptor
		if selected.ok and candidate.ok:
			_activate(active_profile, id, descriptor, candidate)
			manager()._commit_world_restore()
		else:
			manager()._abort_world_restore()
			result.warnings.append("The playthrough was created but could not be selected. Load it again.")
	else: manager()._abort_world_restore()
	return _end(lease, result)


func mutate_slot(reference: StringName, action: String, label: String = "") -> SaveStateResult:
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	var found := _resolve(reference)
	if not found.ok: return _end(lease, found)
	if action == "delete" and found.slot_id == active_slot: return _end(lease, SaveStateResult.outcome(&"active_context", ERR_BUSY, "Select another playthrough before deleting this one."))
	if action != "delete" and not SaveStateCatalogue.label_valid(label): return _end(lease, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Use a nonempty display name of up to 80 characters."))
	var candidate := _read_slot(active_profile, found.slot_id)
	if not candidate.ok: return _end(lease, candidate)
	var metadata: Dictionary = candidate.metadata["catalogue"].duplicate(true)
	var id := found.slot_id
	if action == "duplicate":
		var listing := SaveStateCatalogue.scan(manager(), _context(active_profile).save_root)
		if not listing.ok: return _end(lease, listing)
		if listing.data["entries"].size() >= SaveStateCatalogue.MAX_SLOTS: return _end(lease, SaveStateGenerationSession.failure(ERR_OUT_OF_MEMORY, "The profile has reached its playthrough limit."))
		id = StringName(Crypto.new().generate_random_bytes(16).hex_encode())
		metadata["alias"] = str(id)
		metadata["created_unix"] = int(Time.get_unix_time_from_system())
	metadata["deleted"] = action == "delete"
	if action != "delete": metadata["display_name"] = label
	var result := _write(_context(active_profile), id, candidate.data, metadata, candidate.thumbnail)
	if result.ok and id == active_slot: _slot_metadata["display_name"] = metadata["display_name"]
	return _end(lease, result)


func list_profiles(include_deleted: bool = false) -> SaveStateResult:
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	var result := SaveStateCatalogue.scan(manager(), _context(&"default", true).save_root, true)
	if result.ok and not include_deleted: result.data["entries"] = result.data["entries"].filter(func(e): return not e.get("deleted", false))
	return _end(lease, result)


func create_profile(label: String) -> SaveStateResult:
	if not manager().supports_profiles(): return SaveStateResult.outcome(&"unsupported_capability", ERR_UNAVAILABLE, "Multiple profiles require Pro. The default profile is available in Lite.")
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	if not SaveStateCatalogue.label_valid(label): return _end(lease, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Use a nonempty profile name of up to 80 characters."))
	var listing := SaveStateCatalogue.scan(manager(), _context(&"default", true).save_root, true)
	if not listing.ok: return _end(lease, listing)
	if listing.data["entries"].size() >= SaveStateCatalogue.MAX_PROFILES: return _end(lease, SaveStateGenerationSession.failure(ERR_OUT_OF_MEMORY, "The profile limit has been reached."))
	var id := StringName(Crypto.new().generate_random_bytes(16).hex_encode())
	var result := _write(_context(id, true), id, {"progression": {}, "active_slot": ""}, {"kind": "profile", "display_name": label, "created_unix": int(Time.get_unix_time_from_system()), "deleted": false})
	result = _end(lease, result)
	result.profile_id = id
	return result


func switch_profile(id: StringName, discard_unsaved: bool = false) -> SaveStateResult:
	if id != &"default" and not manager().supports_profiles(): return SaveStateResult.outcome(&"unsupported_capability", ERR_UNAVAILABLE, "Multiple profiles require Pro.")
	if not SaveStateGenerationStore.valid_id(str(id)): return SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Invalid profile ID.")
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	if has_unsaved_changes() and not discard_unsaved: return _end(lease, SaveStateResult.outcome(&"unsaved_changes", ERR_BUSY, "Save or explicitly discard the current changes first."))
	var descriptor := _read_profile(id)
	if not descriptor.ok: return _end(lease, descriptor)
	var slot := StringName(descriptor.data["active_slot"])
	if slot == &"":
		slot = &"main"
		var existing := SaveStateGenerationStore.scan(_context(id).save_root, str(slot))
		if int(existing["error"]) != OK: return _end(lease, SaveStateGenerationSession.failure(int(existing["error"]) as Error, "The profile's playthrough directory cannot be read."))
		if existing["files"].is_empty():
			var created := _write(_context(id), slot, {}, _new_metadata(id, "default", "Playthrough 1"))
			if not created.ok: return _end(lease, created)
	var context := [manager().save_root, manager()._runtime_revision, manager()._migration_revision, manager().get_current_schema_version(), manager()._get_debug_crypto_keys()]
	var candidate := _read_slot(id, slot)
	if not candidate.ok: return _end(lease, candidate)
	if context != [manager().save_root, manager()._runtime_revision, manager()._migration_revision, manager().get_current_schema_version(), manager()._get_debug_crypto_keys()]: return _end(lease, unavailable())
	var staged: SaveStateResult = manager()._stage_world_candidate(candidate.data)
	if not staged.ok: return _end(lease, staged)
	candidate.timings_usec.merge(staged.timings_usec)
	var selected := _selection(descriptor, slot)
	if not selected.ok:
		manager()._abort_world_restore()
		return _end(lease, selected)
	_activate(id, slot, descriptor, candidate)
	manager()._commit_world_restore()
	manager().load_requested.emit()
	manager().apply_saveables_from_bundle(candidate.data.get("__saveables", {}))
	return _end(lease, candidate)


func slot_preview(reference: StringName) -> SaveStateResult:
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	var found := _resolve(reference)
	if not found.ok: return _end(lease, found)
	var result := _read_slot(active_profile, found.slot_id)
	# Preview callers receive metadata and image bytes without applying gameplay state.
	result.data = {}
	return _end(lease, result)


func slot_history(reference: StringName) -> SaveStateResult:
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	var found := _resolve(reference, true)
	if not found.ok: return _end(lease, found)
	var listing := SaveStateGenerationStore.scan(_context(active_profile).save_root, str(found.slot_id))
	if int(listing["error"]) != OK: return _end(lease, SaveStateGenerationSession.failure(int(listing["error"]) as Error, "The history cannot be read."))
	var entries: Array = []
	for file in listing["files"]:
		var candidate := SaveStateGenerationSession.inspect(_context(active_profile), found.slot_id, false, file["id"])
		if candidate.ok and (not SaveStateCatalogue.valid_entry(candidate.metadata.get("catalogue"), false) or candidate.metadata["catalogue"]["profile"] != str(active_profile)):
			candidate = SaveStateGenerationSession.failure(ERR_FILE_CORRUPT, "The playthrough identity is invalid.")
		entries.append({"generation_id": file["id"], "sequence": file["sequence"], "status": str(candidate.status), "message": candidate.message,
			"created_unix": candidate.metadata.get("created_unix", 0), "deleted": candidate.metadata.get("catalogue", {}).get("deleted", false)})
	var result := SaveStateResult.outcome(&"ok", OK)
	result.slot_id = found.slot_id
	result.data = {"generations": entries}
	return _end(lease, result)


## Recovery writes a new generation; loading it is a separate, guarded action.
func recover_slot(reference: StringName, generation: String) -> SaveStateResult:
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	if generation.length() != 32 or not SaveStateGenerationCodec._hex(generation):
		return _end(lease, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Select a generation from this playthrough's history."))
	var found := _resolve(reference, true)
	if not found.ok: return _end(lease, found)
	var candidate := SaveStateGenerationSession.inspect(_context(active_profile), found.slot_id, false, generation)
	if not candidate.ok: return _end(lease, candidate)
	if not SaveStateCatalogue.valid_entry(candidate.metadata.get("catalogue"), false) or candidate.metadata["catalogue"]["profile"] != str(active_profile):
		return _end(lease, SaveStateGenerationSession.failure(ERR_FILE_CORRUPT, "The playthrough identity is invalid."))
	var metadata: Dictionary = candidate.metadata["catalogue"].duplicate(true)
	metadata["deleted"] = false
	metadata["save_kind"] = "recovery"
	metadata["saved_unix"] = int(Time.get_unix_time_from_system())
	var result := _write(_context(active_profile), found.slot_id, candidate.data, metadata, candidate.thumbnail, generation)
	if result.ok:
		result.recovered_from = generation
		result.status = &"recovered"
	return _end(lease, result)


func update_metadata(reference: StringName, changes: Dictionary) -> SaveStateResult:
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	for key in changes:
		if key not in ["location", "scene_id"] or not (changes[key] is String) or changes[key].length() > 256:
			return _end(lease, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Metadata accepts location and scene_id strings of up to 256 characters."))
	var found := _resolve(reference)
	if not found.ok: return _end(lease, found)
	var candidate := _read_slot(active_profile, found.slot_id)
	if not candidate.ok: return _end(lease, candidate)
	var metadata: Dictionary = candidate.metadata["catalogue"].duplicate(true)
	metadata.merge(changes, true)
	var result := _write(_context(active_profile), found.slot_id, candidate.data, metadata, candidate.thumbnail)
	if result.ok and found.slot_id == active_slot: _slot_metadata.merge(changes, true)
	return _end(lease, result)


## Device settings have their own descriptor and never participate in slot restore.
func device_data(value: Variant = null) -> SaveStateResult:
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	var context := SaveStateStorageContext.new(manager(), manager().save_root.path_join(".device"), true)
	var result := SaveStateGenerationSession.inspect(context, &"settings")
	if not result.ok and result.status != &"not_found": return _end(lease, result)
	if value == null:
		if result.status == &"not_found": result = SaveStateResult.outcome(&"ok", OK)
		return _end(lease, result)
	return _end(lease, _write(context, &"settings", value, {"kind": "device"}))


func profile_data(value: Variant = null) -> SaveStateResult:
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	var descriptor := _read_profile(active_profile)
	if not descriptor.ok: return _end(lease, descriptor)
	if value == null:
		var result := SaveStateResult.outcome(&"ok", OK)
		result.data = descriptor.data["progression"].duplicate(true)
		return _end(lease, result)
	var data := descriptor.data.duplicate(true)
	data["progression"] = value
	var result := _write(_context(active_profile, true), active_profile, data, descriptor.metadata["catalogue"])
	if result.ok: _profile = _read_profile(active_profile)
	return _end(lease, result)


func mutate_profile(id: StringName, action: String, label: String = "") -> SaveStateResult:
	if not manager().supports_profiles(): return SaveStateResult.outcome(&"unsupported_capability", ERR_UNAVAILABLE, "Profile management requires Pro.")
	var lease := _begin()
	if lease.is_empty(): return unavailable()
	if action == "delete" and (id == active_profile or id == &"default"): return _end(lease, SaveStateResult.outcome(&"active_context", ERR_BUSY, "The default or active profile cannot be deleted."))
	if action == "rename" and not SaveStateCatalogue.label_valid(label): return _end(lease, SaveStateGenerationSession.failure(ERR_INVALID_PARAMETER, "Use a nonempty profile name of up to 80 characters."))
	var descriptor := _read_profile(id)
	if not descriptor.ok: return _end(lease, descriptor)
	var metadata: Dictionary = descriptor.metadata["catalogue"].duplicate(true)
	metadata["deleted"] = action == "delete"
	if action == "rename": metadata["display_name"] = label
	var result := _write(_context(id, true), id, descriptor.data, metadata)
	if result.ok and id == active_profile: _profile = _read_profile(id)
	result = _end(lease, result)
	result.profile_id = id
	return result
