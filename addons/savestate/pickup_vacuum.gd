extends Node
class_name SaveStatePickupVacuum
## v1.2: one manager per level — removes every node in [member pickup_group] whose [member id_property] matches an id stored in [member SaveManager] (same list as [CollectionLink]: [code]__savestate_collected_ids[/code] by default).

@export var pickup_group: StringName = &"savestate_pickup"
## Property on each pickup node (or ancestor script) holding a unique string id. Falls back to [member Node.name] if unset.
@export var id_property: StringName = &"collection_id"
@export var collected_ids_key: StringName = &"__savestate_collected_ids"


func _ready() -> void:
	_vacuum_pickups()


func _vacuum_pickups() -> void:
	var sm := _get_save_manager()
	if sm == null:
		return
	var raw: Variant = sm.get_value(collected_ids_key, null)
	if raw == null:
		return
	var collected: Dictionary = {}
	if raw is Array:
		for x in raw as Array:
			collected[str(x)] = true
	elif raw is PackedStringArray:
		for x in raw as PackedStringArray:
			collected[str(x)] = true
	else:
		return
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group(pickup_group):
		if not (n is Node):
			continue
		var node: Node = n
		var idv: String = _resolve_pickup_id(node)
		if idv.is_empty():
			continue
		if collected.has(idv):
			node.queue_free()


func _resolve_pickup_id(node: Node) -> String:
	var want := String(id_property)
	if want.is_empty():
		return str(node.name)
	for p in node.get_property_list():
		if str(p.get("name", "")) == want:
			return str(node.get(want))
	return str(node.name)


func _get_save_manager() -> Node:
	var st := get_tree()
	if st == null:
		return null
	return st.root.get_node_or_null("SaveManager") as Node
