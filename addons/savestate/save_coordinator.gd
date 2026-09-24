@tool
class_name SaveStateCoordinator
extends RefCounted
## Main-thread root reservations cover queued work as well as active workers.
## This coordinates addon instances in one process; it is not a filesystem lock.

static var _owners: Dictionary = {}
static var _operations: int = 0


static func root_key(path: String) -> String:
	var key := ProjectSettings.globalize_path(path).simplify_path().trim_suffix("/")
	return key.to_lower() if OS.get_name() == "Windows" else key


static func acquire(path: String, owner: int) -> String:
	var key := root_key(path)
	for held in _owners:
		if _related(key, held) and _owners[held]["owner"] != owner: return ""
	if not _owners.has(key):
		_owners[key] = {"owner": owner, "count": 0}
	_owners[key]["count"] += 1
	return key


static func release(key: String) -> void:
	if key.is_empty() or not _owners.has(key):
		return
	_owners[key]["count"] -= 1
	if _owners[key]["count"] == 0:
		_owners.erase(key)


static func occupied(path: String) -> bool:
	var key := root_key(path)
	for held in _owners:
		if _related(key, held): return true
	return false


static func _related(first: String, second: String) -> bool:
	return first == second or first.begins_with(second + "/") or second.begins_with(first + "/")


static func next_operation() -> String:
	_operations += 1
	return "%d-%d" % [OS.get_process_id(), _operations]


static func editor_game_running() -> bool:
	# EditorInterface does not exist in export templates, even in an unreachable branch.
	if not Engine.is_editor_hint() or not Engine.has_singleton("EditorInterface"):
		return false
	return bool(Engine.get_singleton("EditorInterface").call("is_playing_scene"))
