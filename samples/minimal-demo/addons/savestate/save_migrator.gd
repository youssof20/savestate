class_name SaveMigrator
extends RefCounted
## Deep-merge helpers for schema migration: missing keys from [param defaults] are filled without overwriting existing nested keys from [param current].


static func deep_merge(current: Dictionary, defaults: Dictionary) -> Dictionary:
	var out := current.duplicate(true)
	for key in defaults:
		var dv: Variant = defaults[key]
		if not out.has(key):
			out[key] = _duplicate_value(dv)
			continue
		var cv: Variant = out[key]
		if typeof(dv) == TYPE_DICTIONARY and typeof(cv) == TYPE_DICTIONARY:
			out[key] = deep_merge(cv, dv)
	return out


static func _duplicate_value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			return (v as Dictionary).duplicate(true)
		TYPE_ARRAY:
			return (v as Array).duplicate(true)
		_:
			return v
