extends Node
class_name SaveComponent
## Lite v1.2: drop as a child of a node (e.g. Player), list property names in [member tracked_properties]. Participates in [method SaveManagerBase.persist_including_saveables] via the [code]savestate_saveable[/code] group — no manual dictionary wiring.

@export var storage_key: StringName = &"entity"
@export var tracked_properties: PackedStringArray = []


func _enter_tree() -> void:
	add_to_group("savestate_saveable")


func _exit_tree() -> void:
	if is_instance_valid(self):
		remove_from_group("savestate_saveable")


func get_storage_key() -> StringName:
	return storage_key


func collect_snapshot() -> Dictionary:
	var target: Node = get_parent() if get_parent() else self
	var out := {}
	var valid := {}
	for p in target.get_property_list():
		valid[str(p.get("name", ""))] = true
	for pname in tracked_properties:
		if pname.is_empty():
			continue
		if not valid.has(pname):
			push_warning("SaveComponent: parent has no property '%s' (%s)" % [pname, target.name])
			continue
		out[pname] = target.get(pname)
	return out


func apply_snapshot(data: Dictionary) -> void:
	var target: Node = get_parent() if get_parent() else self
	for key in data:
		var ks := str(key)
		var found := false
		for p in target.get_property_list():
			if str(p.get("name", "")) == ks:
				found = true
				break
		if found:
			target.set(ks, data[key])
