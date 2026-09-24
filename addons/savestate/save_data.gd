class_name SaveStateData
extends RefCounted
## Plain-data checks and typed leaf edits shared by save jobs and editor patches.


static func invalid_path(value: Variant, path: String = "data", depth: int = 0) -> String:
	if depth > 64:
		return path
	if typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
		return path
	if value is Dictionary:
		for key in value:
			var bad := invalid_path(key, path + ".<key>", depth + 1)
			if not bad.is_empty():
				return bad
			bad = invalid_path(value[key], path + "[" + var_to_str(key) + "]", depth + 1)
			if not bad.is_empty():
				return bad
	elif value is Array:
		for index in value.size():
			var bad := invalid_path(value[index], "%s[%d]" % [path, index], depth + 1)
			if not bad.is_empty():
				return bad
	return ""


static func patch(document: Dictionary, operations: Array) -> Dictionary:
	if operations.size() > 4096 or not invalid_path(operations).is_empty():
		return {"error": ERR_INVALID_DATA}
	var candidate := document.duplicate(true)
	for operation in operations:
		if not (operation is Dictionary) or not (operation.get("path") is Array):
			return {"error": ERR_INVALID_DATA}
		var action: String = operation.get("action", "set")
		if action not in ["set", "insert", "remove"] or (action != "remove" and not operation.has("value")):
			return {"error": ERR_INVALID_DATA}
		var path: Array = operation["path"]
		if path.is_empty() or path.size() > 64: return {"error": ERR_INVALID_DATA}
		var container: Variant = candidate
		for index in path.size():
			var segment: Variant = path[index]
			if not (segment is Dictionary) or segment.size() != 1: return {"error": ERR_INVALID_DATA}
			var last := index == path.size() - 1
			var key: Variant
			if container is Dictionary and segment.has("key"):
				key = segment["key"]
				if last and action == "insert":
					if container.has(key): return {"error": ERR_BUSY}
				elif not container.has(key): return {"error": ERR_INVALID_DATA}
			elif (container is Array or typeof(container) >= TYPE_PACKED_BYTE_ARRAY) and segment.get("index") is int:
				key = segment["index"]
				if key < 0 or key > container.size() or (key == container.size() and not (last and action == "insert")):
					return {"error": ERR_INVALID_DATA}
			else: return {"error": ERR_INVALID_DATA}
			if not last:
				container = container[key]
				continue
			if operation.has("before") and (action == "insert" or not same_value(container[key], operation["before"])):
				return {"error": ERR_BUSY}
			if action == "remove":
				if container is Dictionary: container.erase(key)
				elif container is Array: container.remove_at(key)
				else: return {"error": ERR_UNAVAILABLE}
			elif action == "insert":
				if container is Dictionary: container[key] = operation["value"]
				elif container is Array: container.insert(key, operation["value"])
				else: return {"error": ERR_UNAVAILABLE}
			else:
				if typeof(container[key]) != typeof(operation["value"]): return {"error": ERR_INVALID_DATA}
				# Packed values are copied Variants: replace the owning property as a whole.
				if not (container is Dictionary or container is Array): return {"error": ERR_UNAVAILABLE}
				container[key] = operation["value"]
	return {"error": OK, "data": candidate}


static func same_value(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and var_to_bytes(a) == var_to_bytes(b)
