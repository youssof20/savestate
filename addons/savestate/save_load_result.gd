class_name SaveStateLoadResult
extends SaveStateResult
## A decoded candidate or a specific failure. A successful empty dictionary has ok = true.



static func success(candidate: Dictionary, schema: int) -> SaveStateLoadResult:
	var result := SaveStateLoadResult.new()
	result.ok = true
	result.status = &"ok"
	result.error = OK
	result.data = candidate
	result.schema_version = schema
	return result


static func failure(code: StringName, engine_error: Error, explanation: String, location: String = "") -> SaveStateLoadResult:
	var result := SaveStateLoadResult.new()
	result.status = code
	result.error = engine_error
	result.message = explanation
	result.data_path = location
	return result


func as_dictionary() -> Dictionary:
	return {"ok": ok, "status": status, "error": error, "message": message,
		"data": data.duplicate(true), "schema_version": schema_version, "data_path": data_path}
