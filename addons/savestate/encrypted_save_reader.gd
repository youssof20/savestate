extends RefCounted
## Decrypts Pro’s outer save wrapper (AES-256-CBC + HMAC) for editor health checks in Lite.
## Mirrors [code]addons/savestate_pro/save_security.gd[/code] constants and [method open_outer_save_file] so Lite does not reference Pro scripts at parse time.

const OUTER_FORMAT_VERSION: int = 2
const IV_SIZE: int = 16
const HMAC_SIZE: int = 32
const AES_KEY_SIZE: int = 32


static func open_outer_save_file(
		outer_file: PackedByteArray,
		aes_key: PackedByteArray,
		hmac_key: PackedByteArray
	) -> Dictionary:
	if aes_key.size() != AES_KEY_SIZE or hmac_key.is_empty():
		return {"error": ERR_UNCONFIGURED}
	if outer_file.size() < SaveFormat.HEADER_SIZE + IV_SIZE + HMAC_SIZE:
		return {"error": ERR_FILE_CORRUPT}

	var h := SaveFormat.parse_header(outer_file)
	if int(h.get("error", OK)) != OK:
		return {"error": ERR_FILE_UNRECOGNIZED}
	if int(h["format_version"]) != OUTER_FORMAT_VERSION or int(h["flags"]) != 0 or int(h["schema_version"]) != 0:
		return {"error": ERR_FILE_UNRECOGNIZED}

	var payload_len: int = int(h["payload_len"])
	var expected_total := SaveFormat.HEADER_SIZE + payload_len + HMAC_SIZE
	if outer_file.size() != expected_total or payload_len < IV_SIZE + 16 or (payload_len - IV_SIZE) % 16 != 0:
		return {"error": ERR_FILE_CORRUPT}

	var header := outer_file.slice(0, SaveFormat.HEADER_SIZE)
	var body := outer_file.slice(SaveFormat.HEADER_SIZE, SaveFormat.HEADER_SIZE + payload_len)
	var mac := outer_file.slice(SaveFormat.HEADER_SIZE + payload_len, expected_total)

	var crypto := Crypto.new()
	var to_mac := header.duplicate()
	to_mac.append_array(body)
	var expect_mac := crypto.hmac_digest(HashingContext.HASH_SHA256, hmac_key, to_mac)
	if not crypto.constant_time_compare(expect_mac, mac):
		return {"error": ERR_INVALID_DATA}

	if body.size() < IV_SIZE:
		return {"error": ERR_FILE_CORRUPT}
	var iv := body.slice(0, IV_SIZE)
	var ciphertext := body.slice(IV_SIZE, body.size())
	var dec_padded := _aes_cbc_decrypt(ciphertext, aes_key, iv)
	if dec_padded.is_empty():
		return {"error": ERR_INVALID_DATA}
	var inner := _unpad_pkcs7(dec_padded)
	if inner.is_empty():
		return {"error": ERR_INVALID_DATA}
	return {"error": OK, "inner": inner}


static func _aes_cbc_decrypt(ciphertext: PackedByteArray, key: PackedByteArray, iv: PackedByteArray) -> PackedByteArray:
	if key.size() != AES_KEY_SIZE or iv.size() != IV_SIZE or ciphertext.is_empty() or ciphertext.size() % 16 != 0:
		return PackedByteArray()
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_DECRYPT, key, iv) != OK:
		return PackedByteArray()
	var out := aes.update(ciphertext)
	aes.finish()
	return out


static func _unpad_pkcs7(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return data
	var pad_len: int = int(data[data.size() - 1])
	if pad_len < 1 or pad_len > 16 or pad_len > data.size():
		return PackedByteArray()
	for index in range(data.size() - pad_len, data.size()):
		if data[index] != pad_len:
			return PackedByteArray()
	return data.slice(0, data.size() - pad_len)
