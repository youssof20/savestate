@tool
class_name AtomicWriter
extends RefCounted
## Serializes in-process writes and retains the prior main until replacement succeeds.
## This is not a cross-process lock or a power-loss durability guarantee.

static var _mutex := Mutex.new()
static var _sequence: int = 0


static func write_atomic(destination_path: String, data: PackedByteArray, backup_previous: bool = false) -> Error:
	return _write_guarded(destination_path, data, backup_previous, "")


static func write_atomic_if_unchanged(path: String, data: PackedByteArray, backup: bool, expected_hash: String) -> Error:
	if expected_hash.is_empty():
		return ERR_INVALID_PARAMETER
	return _write_guarded(path, data, backup, expected_hash)


static func write_task(path: String, data: PackedByteArray, backup: bool, transfer: Dictionary) -> void:
	transfer["error"] = write_atomic(path, data, backup)


static func _write_guarded(path: String, data: PackedByteArray, backup: bool, expected_hash: String) -> Error:
	_mutex.lock()
	var error := _write_locked(path, data, backup, expected_hash)
	_mutex.unlock()
	return error


static func _write_locked(path: String, data: PackedByteArray, backup: bool, expected_hash: String) -> Error:
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	if not expected_hash.is_empty() and FileAccess.get_sha256(path) != expected_hash:
		return ERR_BUSY
	_sequence += 1
	var temporary := "%s.tmp.%d.%d" % [path, OS.get_process_id(), _sequence]
	var error := _write_all_bytes(temporary, data)
	if error == OK:
		error = _verify_read_matches(temporary, data)
	if error == OK:
		error = _commit_replace(temporary, path, backup)
	_try_remove_file(temporary)
	return error


static func _write_all_bytes(path: String, data: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(data)
	file.flush()
	var error := file.get_error()
	file.close()
	return error


static func _verify_read_matches(path: String, expected: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var matches := file.get_length() == expected.size()
	if matches:
		matches = file.get_buffer(expected.size()) == expected and file.get_error() == OK
	file.close()
	return OK if matches else ERR_FILE_CORRUPT


## Optional rename callable permits deterministic filesystem-failure tests.
static func _commit_replace(temporary: String, destination: String, backup: bool, rename: Callable = Callable()) -> Error:
	if not FileAccess.file_exists(temporary):
		return ERR_FILE_NOT_FOUND
	var previous := destination + ".rollback." + str(OS.get_process_id()) + "." + str(Time.get_ticks_usec())
	var had_previous := FileAccess.file_exists(destination)
	if had_previous:
		var moved := _rename(destination, previous, rename)
		if moved != OK:
			return moved
	var installed := _rename(temporary, destination, rename)
	if installed != OK:
		if had_previous and _rename(previous, destination, rename) != OK:
			push_warning("SaveState: replacement failed; the prior save remains at " + previous)
		return installed
	# Commit point: the verified candidate has its final name. Cleanup must not report a false failed save.
	if had_previous and backup:
		var backup_path := destination + ".bak"
		var old_backup := previous + ".bak"
		var had_backup := FileAccess.file_exists(backup_path)
		if had_backup and _rename(backup_path, old_backup, rename) != OK:
			push_warning("SaveState: save committed; prior save retained at " + previous)
			return OK
		if _rename(previous, backup_path, rename) != OK:
			if had_backup:
				_rename(old_backup, backup_path, rename)
			push_warning("SaveState: save committed; prior save retained at " + previous)
			return OK
		_try_remove_file(old_backup)
	elif had_previous:
		_try_remove_file(previous)
	return OK


static func _rename(from: String, to: String, operation: Callable) -> Error:
	if operation.is_valid():
		return int(operation.call(from, to)) as Error
	return DirAccess.rename_absolute(from, to)


static func _try_remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
