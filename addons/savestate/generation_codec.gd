class_name SaveStateGenerationCodec
extends RefCounted
## Version 3 uses bounded tagged JSON for containers and native bytes for scalar leaves.
## Integers never pass through JSON numbers. Objects and typed containers are not accepted.

const MAX_BYTES := 16 * 1024 * 1024
const MAX_ITEMS := 100000
const MAX_DEPTH := 32
const MAX_LEAF := 1024 * 1024
const MAX_THUMBNAIL := 256 * 1024
const MAGIC := "SSG3"
const HEADER := 48
const LEAVES := [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME,
	TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_COLOR]


static func digest(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish()


static func encode(document: Dictionary) -> Dictionary:
	var state := {"count": 0, "bytes": 0, "error": "", "path": []}
	var tagged: Variant = _encode_value(document, [], [], state)
	if not str(state["error"]).is_empty():
		return {"error": state.get("code", ERR_INVALID_DATA), "message": state["error"], "typed_path": state["path"]}
	var body := JSON.stringify(tagged).to_utf8_buffer()
	if body.size() + HEADER > MAX_BYTES:
		return {"error": ERR_OUT_OF_MEMORY, "message": "The encoded generation exceeds 16 MiB."}
	var bytes := PackedByteArray()
	bytes.resize(HEADER)
	for index in 4:
		bytes[index] = MAGIC.to_ascii_buffer()[index]
	bytes.encode_u32(4, 3)
	bytes.encode_u64(8, body.size())
	var checksum := digest(body)
	for index in 32:
		bytes[16 + index] = checksum[index]
	bytes.append_array(body)
	return {"error": OK, "bytes": bytes}


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER or bytes.size() > MAX_BYTES or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return {"error": ERR_FILE_CORRUPT}
	if bytes.decode_u32(4) != 3:
		return {"error": ERR_FILE_UNRECOGNIZED}
	if bytes.decode_u64(8) != bytes.size() - HEADER:
		return {"error": ERR_FILE_CORRUPT}
	var body := bytes.slice(HEADER)
	if digest(body) != bytes.slice(16, HEADER) or not _bounded_json(body):
		return {"error": ERR_FILE_CORRUPT}
	var state := {"count": 0, "error": "", "path": []}
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {"error": ERR_FILE_CORRUPT}
	var document: Variant = _decode_value(json.data, [], state)
	if not str(state["error"]).is_empty() or not (document is Dictionary):
		return {"error": ERR_INVALID_DATA, "typed_path": state["path"]}
	return {"error": OK, "document": document}


static func _bad(state: Dictionary, path: Array, explanation: String) -> Variant:
	state["error"] = explanation
	state["path"] = path.duplicate(true)
	return null


static func _encode_value(value: Variant, path: Array, ancestors: Array, state: Dictionary) -> Variant:
	state["count"] += 1
	state["bytes"] += 16
	if state["count"] > MAX_ITEMS or path.size() > MAX_DEPTH:
		return _bad(state, path, "The data exceeds the nesting or element limit.")
	var kind := typeof(value)
	if kind == TYPE_PACKED_BYTE_ARRAY:
		state["bytes"] += value.size() * 2
		if value.size() > MAX_LEAF:
			state["code"] = ERR_OUT_OF_MEMORY
			return _bad(state, path, "The byte array exceeds 1 MiB.")
		if state["bytes"] > MAX_BYTES:
			state["code"] = ERR_OUT_OF_MEMORY
			return _bad(state, path, "The encoded generation exceeds 16 MiB.")
		return ["b", value.hex_encode()]
	if kind in [TYPE_ARRAY, TYPE_DICTIONARY]:
		if value.is_typed():
			return _bad(state, path, "Convert typed containers to plain arrays or dictionaries before saving.")
		for ancestor in ancestors:
			if is_same(value, ancestor):
				return _bad(state, path, "Cyclic containers cannot be saved.")
		if value.size() > MAX_ITEMS:
			return _bad(state, path, "The container exceeds the element limit.")
		var parents := ancestors.duplicate()
		parents.append(value)
		var items: Array = []
		for key in value if kind == TYPE_DICTIONARY else range(value.size()):
			var child := path.duplicate()
			child.append({"key": key} if kind == TYPE_DICTIONARY else {"index": key})
			if kind == TYPE_DICTIONARY:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT, TYPE_BOOL]:
					return _bad(state, path, "Dictionary keys must be strings, StringNames, integers, or booleans.")
				items.append([_encode_value(key, child, parents, state), _encode_value(value[key], child, parents, state)])
			else:
				items.append(_encode_value(value[key], child, parents, state))
			if not str(state["error"]).is_empty():
				return null
		return ["d" if kind == TYPE_DICTIONARY else "a", items]
	if kind >= TYPE_PACKED_BYTE_ARRAY and kind <= TYPE_PACKED_VECTOR4_ARRAY:
		if value.size() > MAX_ITEMS:
			return _bad(state, path, "The packed array exceeds the element limit.")
		var items: Array = []
		for index in value.size():
			items.append(_encode_value(value[index], path + [{"index": index}], ancestors, state))
		return [str(kind), items]
	if kind not in LEAVES or not _finite(value):
		return _bad(state, path, "This value type is unsupported or contains a non-finite number.")
	var bytes := var_to_bytes(value)
	state["bytes"] += bytes.size() * 2
	if bytes.size() > MAX_LEAF:
		state["code"] = ERR_OUT_OF_MEMORY
		return _bad(state, path, "The scalar exceeds 1 MiB.")
	if state["bytes"] > MAX_BYTES:
		state["code"] = ERR_OUT_OF_MEMORY
		return _bad(state, path, "The encoded generation exceeds 16 MiB.")
	return ["v", bytes.hex_encode()]


static func _decode_value(tagged: Variant, path: Array, state: Dictionary) -> Variant:
	state["count"] += 1
	if state["count"] > MAX_ITEMS or path.size() > MAX_DEPTH or not (tagged is Array) or tagged.size() != 2 or not (tagged[0] is String):
		return _bad(state, path, "Invalid tagged value.")
	var tag: String = tagged[0]
	if tag == "b":
		if not (tagged[1] is String) or tagged[1].length() > MAX_LEAF * 2 or not _hex(tagged[1]):
			return _bad(state, path, "Invalid byte array.")
		return tagged[1].hex_decode()
	if tag == "v":
		if not (tagged[1] is String) or tagged[1].length() > MAX_LEAF * 2 or not _hex(tagged[1]):
			return _bad(state, path, "Invalid scalar bytes.")
		var bytes: PackedByteArray = tagged[1].hex_decode()
		if bytes.size() < 4 or (bytes.decode_u32(0) & 0xffff) not in LEAVES:
			return _bad(state, path, "Unsupported scalar type.")
		var kind := bytes.decode_u32(0) & 0xffff
		var wide := (bytes.decode_u32(0) & 0x10000) != 0
		var minimum := {TYPE_NIL: 4, TYPE_BOOL: 8, TYPE_INT: 12 if wide else 8, TYPE_FLOAT: 12 if wide else 8,
			TYPE_VECTOR2: 20 if wide else 12, TYPE_VECTOR2I: 12, TYPE_VECTOR3: 28 if wide else 16,
			TYPE_VECTOR3I: 16, TYPE_VECTOR4: 36 if wide else 20, TYPE_VECTOR4I: 20, TYPE_COLOR: 20,
			TYPE_STRING: 8, TYPE_STRING_NAME: 8}
		if bytes.size() < int(minimum[kind]):
			return _bad(state, path, "Truncated scalar encoding.")
		if kind in [TYPE_STRING, TYPE_STRING_NAME]:
			if bytes.size() < 8 or bytes.decode_u32(4) > bytes.size() - 8 \
					or not _valid_utf8(bytes.slice(8, 8 + bytes.decode_u32(4))):
				return _bad(state, path, "Invalid string encoding.")
		# Native decoding is restricted to bounded scalar types, with executable objects disabled.
		var value: Variant = bytes_to_var(bytes)
		if typeof(value) != kind or var_to_bytes(value) != bytes or not _finite(value):
			return _bad(state, path, "Invalid scalar encoding.")
		return value
	if not (tagged[1] is Array) or tagged[1].size() > MAX_ITEMS:
		return _bad(state, path, "Invalid container.")
	var items: Array = tagged[1]
	if tag == "d":
		var output := {}
		for entry in items:
			if not (entry is Array) or entry.size() != 2:
				return _bad(state, path, "Invalid dictionary entry.")
			var key: Variant = _decode_value(entry[0], path, state)
			if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT, TYPE_BOOL] or output.has(key):
				return _bad(state, path, "Invalid or duplicate dictionary key.")
			output[key] = _decode_value(entry[1], path + [{"key": key}], state)
			if not str(state["error"]).is_empty():
				return null
		return output
	var output: Array = []
	for index in items.size():
		output.append(_decode_value(items[index], path + [{"index": index}], state))
		if not str(state["error"]).is_empty():
			return null
	if tag == "a":
		return output
	if not tag.is_valid_int():
		return _bad(state, path, "Unknown container tag.")
	var kind := int(tag)
	var expected := {TYPE_PACKED_BYTE_ARRAY: TYPE_INT, TYPE_PACKED_INT32_ARRAY: TYPE_INT, TYPE_PACKED_INT64_ARRAY: TYPE_INT,
		TYPE_PACKED_FLOAT32_ARRAY: TYPE_FLOAT, TYPE_PACKED_FLOAT64_ARRAY: TYPE_FLOAT, TYPE_PACKED_STRING_ARRAY: TYPE_STRING,
		TYPE_PACKED_VECTOR2_ARRAY: TYPE_VECTOR2, TYPE_PACKED_VECTOR3_ARRAY: TYPE_VECTOR3, TYPE_PACKED_COLOR_ARRAY: TYPE_COLOR,
		TYPE_PACKED_VECTOR4_ARRAY: TYPE_VECTOR4}
	if not expected.has(kind):
		return _bad(state, path, "Unknown packed array type.")
	for value in output:
		if typeof(value) != expected[kind] or (kind == TYPE_PACKED_BYTE_ARRAY and (value < 0 or value > 255)) \
				or (kind == TYPE_PACKED_INT32_ARRAY and (value < -2147483648 or value > 2147483647)) \
				or (kind == TYPE_PACKED_FLOAT32_ARRAY and absf(value) > 3.4028234663852886e38):
			return _bad(state, path, "Invalid packed array element.")
	match kind:
		TYPE_PACKED_BYTE_ARRAY: return PackedByteArray(output)
		TYPE_PACKED_INT32_ARRAY: return PackedInt32Array(output)
		TYPE_PACKED_INT64_ARRAY: return PackedInt64Array(output)
		TYPE_PACKED_FLOAT32_ARRAY: return PackedFloat32Array(output)
		TYPE_PACKED_FLOAT64_ARRAY: return PackedFloat64Array(output)
		TYPE_PACKED_STRING_ARRAY: return PackedStringArray(output)
		TYPE_PACKED_VECTOR2_ARRAY: return PackedVector2Array(output)
		TYPE_PACKED_VECTOR3_ARRAY: return PackedVector3Array(output)
		TYPE_PACKED_COLOR_ARRAY: return PackedColorArray(output)
		TYPE_PACKED_VECTOR4_ARRAY: return PackedVector4Array(output)
	return null


static func _finite(value: Variant) -> bool:
	match typeof(value):
		TYPE_FLOAT: return is_finite(value)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4: return value.is_finite()
		TYPE_COLOR: return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	return true


static func _hex(value: String) -> bool:
	if value.length() % 2 != 0:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func _bounded_json(bytes: PackedByteArray) -> bool:
	if not _valid_utf8(bytes):
		return false
	var depth := 0
	var separators := 0
	var quoted := false
	var escaped := false
	for byte in bytes:
		if quoted:
			if escaped: escaped = false
			elif byte == 92: escaped = true
			elif byte == 34: quoted = false
		elif byte == 34: quoted = true
		elif byte == 91 or byte == 123:
			depth += 1
			separators += 1
			if depth > MAX_DEPTH * 4 + 8 or separators > MAX_ITEMS * 4:
				return false
		elif byte == 93 or byte == 125:
			depth -= 1
			if depth < 0: return false
	return depth == 0 and not quoted


static func _valid_utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	while index < bytes.size():
		var first := bytes[index]
		var count := 0
		var code := 0
		if first < 128:
			index += 1
			continue
		elif first >= 194 and first <= 223:
			count = 1
			code = first & 31
		elif first >= 224 and first <= 239:
			count = 2
			code = first & 15
		elif first >= 240 and first <= 244:
			count = 3
			code = first & 7
		else: return false
		if index + count >= bytes.size(): return false
		for offset in range(1, count + 1):
			var next := bytes[index + offset]
			if next < 128 or next > 191: return false
			code = (code << 6) | (next & 63)
		if (count == 2 and code < 2048) or (count == 3 and code < 65536) or code > 1114111 or (code >= 55296 and code <= 57343):
			return false
		index += count + 1
	return true
