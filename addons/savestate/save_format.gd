class_name SaveFormat
extends RefCounted
## On-disk envelope for Lite (plain). Pro wraps payload with [SaveSecurity] before writing.

const MAGIC: String = "SSP1"
const HEADER_SIZE: int = 20


static func build_header(format_version: int, schema_version: int, flags: int, payload_len: int) -> PackedByteArray:
	var buf := MAGIC.to_ascii_buffer()
	buf.resize(HEADER_SIZE)
	buf.encode_u32(4, format_version)
	buf.encode_u32(8, schema_version)
	buf.encode_u32(12, flags)
	buf.encode_u32(16, payload_len)
	return buf


static func parse_header(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE:
		return {"error": ERR_FILE_CORRUPT}
	if bytes.slice(0, 4) != MAGIC.to_ascii_buffer():
		return {"error": ERR_FILE_UNRECOGNIZED}
	return {
		"format_version": bytes.decode_u32(4),
		"schema_version": bytes.decode_u32(8),
		"flags": bytes.decode_u32(12),
		"payload_len": bytes.decode_u32(16),
		"error": OK,
	}
