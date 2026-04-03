extends Node
class_name CollectionLink
## Lite v1.2: put on a pickup/chest. If [member collection_id] was marked collected (see [method mark_collected]), this node [method queue_free]s on load so the object stays gone across scenes.

const KV_COLLECTED: StringName = &"__savestate_collected_ids"

@export var collection_id: StringName = &"coin_main_01"


func _ready() -> void:
	if _is_already_collected():
		queue_free()


func _is_already_collected() -> bool:
	var sm := _save_manager()
	if sm == null:
		return false
	var raw: Variant = sm.get_value(KV_COLLECTED, null)
	if raw == null:
		return false
	if raw is Array:
		return (raw as Array).has(str(collection_id)) or (raw as Array).has(collection_id)
	if raw is PackedStringArray:
		return (raw as PackedStringArray).has(str(collection_id))
	return false


## Call when the player collects this object (then [method queue_free] or hide the node). Uses [method SaveManagerBase.mark_dirty] if available.
func mark_collected() -> void:
	var sm := _save_manager()
	if sm == null:
		return
	var arr: Array = []
	var raw: Variant = sm.get_value(KV_COLLECTED, null)
	if raw is Array:
		arr = (raw as Array).duplicate()
	elif raw is PackedStringArray:
		for s in raw as PackedStringArray:
			arr.append(str(s))
	var sid := str(collection_id)
	if not arr.has(sid):
		arr.append(sid)
	sm.set_value(KV_COLLECTED, arr)
	if sm.has_method("mark_dirty"):
		sm.call("mark_dirty")
	else:
		sm.persist()


func _save_manager() -> Node:
	var st := get_tree()
	if st == null:
		return null
	return st.root.get_node_or_null("SaveManager") as Node
