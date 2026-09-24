class_name SaveStateResult
extends RefCounted
## Shared operation outcome. Identity refers to the captured operation, never the current selection.

var operation_id: String = ""
var ok: bool = false
var status: StringName = &"corrupt"
var error: Error = ERR_FILE_CORRUPT
var message: String = ""
var slot_id: StringName = &""
var profile_id: StringName = &"default"
var generation_id: String = ""
var sequence: int = 0
var recovered_from: String = ""
var warnings: PackedStringArray = []
var timings_usec: Dictionary = {}
var path: String = ""
var data_path: String = ""
var typed_path: Array = []
var data: Dictionary = {}
var schema_version: int = 0
var thumbnail: PackedByteArray = []
var metadata: Dictionary = {}


static func outcome(code: StringName, engine_error: Error, explanation: String = "") -> SaveStateResult:
	var result := SaveStateResult.new()
	result.ok = engine_error == OK
	result.status = code
	result.error = engine_error
	result.message = explanation
	return result
