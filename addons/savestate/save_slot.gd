class_name SaveSlot
extends Resource
## Logical save slot metadata. Paths are resolved by the [code]SaveManager[/code] autoload using [member SaveManagerBase.save_root].

@export var slot_id: StringName = &"slot_0"
@export var display_name: String = "Save"
## File name without extension under [member SaveManagerBase.save_root] (e.g. [code]save1[/code]).
@export var file_base_name: String = "save"
@export var last_modified_unix: int = 0
## Schema version last read from disk (migration / debugging).
@export var file_schema_version: int = 0
@export var screenshot_path: String = ""
## Optional cache of last loaded raw bytes (editor / debug; can be large).
@export var data_buffer: PackedByteArray = PackedByteArray()


func get_file_path(save_root: String, use_json: bool) -> String:
	var ext := ".json" if use_json else ".bin"
	var dir := save_root.strip_edges()
	if not dir.ends_with("/"):
		dir += "/"
	return dir.path_join(file_base_name + ext)


func get_temp_path(save_root: String, use_json: bool) -> String:
	return get_file_path(save_root, use_json) + ".tmp"
