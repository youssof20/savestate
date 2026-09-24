@tool
class_name SaveStateEditDocument
extends RefCounted
## The original typed document remains authoritative; rows are only a view.

var document: Dictionary = {}
var paths: Dictionary = {}
var values: Dictionary = {}


func open(data: Dictionary) -> Dictionary:
	document = data.duplicate(true)
	paths.clear()
	values.clear()
	_visit(document, [], "$", 0)
	return values.duplicate(true)


func _visit(value: Variant, path: Array, label: String, depth: int) -> void:
	if depth < 64 and value is Dictionary and not value.is_empty():
		for key in value:
			_visit(value[key], path + [{"key": key}], label + "[" + var_to_str(key) + "]", depth + 1)
	elif depth < 64 and value is Array and not value.is_empty():
		for index in value.size():
			_visit(value[index], path + [{"index": index}], "%s[%d]" % [label, index], depth + 1)
	elif not path.is_empty():
		paths[label] = path
		values[label] = value


func operations(edited: Dictionary) -> Array:
	var edits: Array = []
	for label in edited:
		if paths.has(label) and not SaveStateData.same_value(values[label], edited[label]):
			edits.append({"path": paths[label].duplicate(true), "before": values[label], "value": edited[label]})
	return edits


func candidate(edited: Dictionary) -> Dictionary:
	return SaveStateData.patch(document, operations(edited))


static func can_edit_text(value: Variant) -> bool:
	return typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]


static func parse_text(text: String, previous: Variant) -> Dictionary:
	var trimmed := text.strip_edges()
	match typeof(previous):
		TYPE_STRING:
			return {"ok": true, "value": text}
		TYPE_STRING_NAME:
			return {"ok": true, "value": StringName(text)}
		TYPE_BOOL:
			if trimmed in ["true", "false"]:
				return {"ok": true, "value": trimmed == "true"}
		TYPE_INT:
			if trimmed.is_valid_int():
				var digits := trimmed.trim_prefix("-").trim_prefix("+")
				while digits.length() > 1 and digits.begins_with("0"):
					digits = digits.substr(1)
				var limit := "9223372036854775808" if trimmed.begins_with("-") else "9223372036854775807"
				if digits.length() > limit.length() or (digits.length() == limit.length() and digits > limit):
					return {"ok": false}
				return {"ok": true, "value": int(trimmed)}
		TYPE_FLOAT:
			if trimmed.is_valid_float() and is_finite(float(trimmed)):
				return {"ok": true, "value": float(trimmed)}
	return {"ok": false}
