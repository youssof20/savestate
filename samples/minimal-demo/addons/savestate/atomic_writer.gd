class_name AtomicWriter
extends RefCounted
## Writes a full payload to [code]destination_path + ".tmp"[/code], verifies it, then commits by rename.
## On Windows, [method DirAccess.rename_absolute] can fail if the destination exists; this helper deletes the destination first.


## If [param backup_previous] is [code]true[/code] and [param destination_path] already exists, it is renamed to [code].bak[/code] before the temp file is committed (rolling backup). SaveManager passes this from [member SaveManagerBase.backup_on_commit] (default [code]true[/code]).
static func write_atomic(destination_path: String, data: PackedByteArray, backup_previous: bool = false) -> Error:
	if destination_path.is_empty():
		return ERR_INVALID_PARAMETER

	var tmp_path := destination_path + ".tmp"
	var err := _write_all_bytes(tmp_path, data)
	if err != OK:
		_try_remove_file(tmp_path)
		return err

	err = _verify_read_matches(tmp_path, data)
	if err != OK:
		_try_remove_file(tmp_path)
		return err

	err = _commit_replace(tmp_path, destination_path, backup_previous)
	if err != OK:
		_try_remove_file(tmp_path)
	return err


static func _write_all_bytes(path: String, data: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(data)
	file.flush()
	var close_err := file.get_error()
	file.close()
	if close_err != OK:
		return close_err
	return OK


static func _verify_read_matches(path: String, expected: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var len: int = int(file.get_length())
	if len != expected.size():
		file.close()
		return ERR_FILE_CORRUPT
	var got := file.get_buffer(len)
	file.close()
	if got != expected:
		return ERR_FILE_CORRUPT
	return OK


static func _commit_replace(tmp_path: String, final_path: String, backup_previous: bool) -> Error:
	if FileAccess.file_exists(final_path):
		if backup_previous:
			var bak_path := final_path + ".bak"
			if FileAccess.file_exists(bak_path):
				var rmb := DirAccess.remove_absolute(bak_path)
				if rmb != OK:
					return rmb
			var rb := DirAccess.rename_absolute(final_path, bak_path)
			if rb != OK:
				return rb
		else:
			var rm_err := DirAccess.remove_absolute(final_path)
			if rm_err != OK:
				return rm_err

	var rename_err := DirAccess.rename_absolute(tmp_path, final_path)
	if rename_err != OK:
		return rename_err
	return OK


static func _try_remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
