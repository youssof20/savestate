@tool
class_name SaveStateEditSession
extends RefCounted
## Typed document snapshots support undo without reconstructing data from display strings.
var original: Dictionary = {}
var current: Dictionary = {}
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []

func open(data: Dictionary) -> void:
	original = data.duplicate(true)
	current = data.duplicate(true)
	undo_stack.clear()
	redo_stack.clear()

func dirty() -> bool:
	return not SaveStateData.same_value(original, current)

func change(operation: Dictionary) -> Error:
	var patched := SaveStateData.patch(current, [operation])
	if patched.error != OK: return patched.error
	var checked := SaveStateGenerationCodec.encode(patched.data)
	if checked.error != OK: return checked.error
	undo_stack.append(current.duplicate(true))
	if undo_stack.size() > 32: undo_stack.pop_front()
	current = patched.data
	redo_stack.clear()
	return OK

func undo() -> void:
	if undo_stack.is_empty(): return
	redo_stack.append(current)
	current = undo_stack.pop_back()

func redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(current)
	current = redo_stack.pop_back()

static func diff(before: Dictionary, after: Dictionary) -> Array:
	var result: Array = []
	_diff(before, after, [], result)
	return result

static func _diff(before: Variant, after: Variant, path: Array, result: Array) -> void:
	if SaveStateData.same_value(before, after): return
	if before is Dictionary and after is Dictionary:
		for key in before:
			if not after.has(key): result.append({"action": "remove", "path": path + [{"key": key}], "before": before[key]})
			else: _diff(before[key], after[key], path + [{"key": key}], result)
		for key in after:
			if not before.has(key): result.append({"action": "insert", "path": path + [{"key": key}], "value": after[key]})
	elif before is Array and after is Array and before.size() == after.size():
		for i in before.size(): _diff(before[i], after[i], path + [{"index": i}], result)
	else: result.append({"action": "set", "path": path, "before": before, "value": after})

static func path_label(path: Array) -> String:
	var label := "$"
	for part in path:
		label += "[" + var_to_str(part.get("key", part.get("index"))) + "]"
	return label

static func summary(value: Variant) -> String:
	if value is Dictionary or value is Array or typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		return "%s · %d items" % [type_string(typeof(value)), value.size()]
	return str(value).left(180)

static func parse(text: String, previous: Variant) -> Dictionary:
	if SaveStateEditDocument.can_edit_text(previous): return SaveStateEditDocument.parse_text(text, previous)
	var kind := typeof(previous)
	var sizes := {TYPE_VECTOR2: 2, TYPE_VECTOR2I: 2, TYPE_VECTOR3: 3, TYPE_VECTOR3I: 3, TYPE_VECTOR4: 4, TYPE_VECTOR4I: 4, TYPE_COLOR: 4, TYPE_QUATERNION: 4}
	if not sizes.has(kind): return {"ok": false}
	var raw := text.replace("(", "").replace(")", "").split(",")
	if raw.size() != sizes[kind]: return {"ok": false}
	var numbers: Array = []
	for item in raw:
		if kind in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I]:
			var parsed := SaveStateEditDocument.parse_text(item, 0)
			if not parsed.ok: return parsed
			numbers.append(parsed.value)
		else:
			if not item.strip_edges().is_valid_float() or not is_finite(float(item)): return {"ok": false}
			numbers.append(float(item))
	var value: Variant
	match kind:
		TYPE_VECTOR2: value = Vector2(numbers[0], numbers[1])
		TYPE_VECTOR2I: value = Vector2i(numbers[0], numbers[1])
		TYPE_VECTOR3: value = Vector3(numbers[0], numbers[1], numbers[2])
		TYPE_VECTOR3I: value = Vector3i(numbers[0], numbers[1], numbers[2])
		TYPE_VECTOR4: value = Vector4(numbers[0], numbers[1], numbers[2], numbers[3])
		TYPE_VECTOR4I: value = Vector4i(numbers[0], numbers[1], numbers[2], numbers[3])
		TYPE_COLOR: value = Color(numbers[0], numbers[1], numbers[2], numbers[3])
		TYPE_QUATERNION: value = Quaternion(numbers[0], numbers[1], numbers[2], numbers[3])
	return {"ok": true, "value": value}
