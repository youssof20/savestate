@tool
class_name SaveStateStorageContext
extends RefCounted
## A main-thread view of storage configuration, without changing the manager's save root.

var owner_ref: WeakRef
var save_root: String
var metadata_only: bool = false
var generation_retention: int = 5
var _runtime_revision: int = 0
var _cache_epoch: int = 0


func _init(manager: Node, root: String, metadata: bool = false) -> void:
	owner_ref = weakref(manager)
	save_root = root
	metadata_only = metadata
	generation_retention = 2 if metadata else manager.generation_retention
	_runtime_revision = manager._runtime_revision
	_cache_epoch = manager._cache_epoch


func _validate_write_configuration() -> Error:
	return owner_ref.get_ref()._validate_write_configuration()


func storage_owner_id() -> int:
	return owner_ref.get_ref().get_instance_id()


func _validate_loaded_data(data: Dictionary) -> String:
	return "" if metadata_only else owner_ref.get_ref()._validate_loaded_data(data)


func get_current_schema_version() -> int:
	return 1 if metadata_only else owner_ref.get_ref().get_current_schema_version()


func _pre_write_transform(bytes: PackedByteArray) -> PackedByteArray:
	return owner_ref.get_ref()._pre_write_transform(bytes)


func _get_debug_crypto_keys() -> Dictionary:
	return owner_ref.get_ref()._get_debug_crypto_keys()


func _run_schema_migration_pipeline(data: Dictionary, schema: int) -> SaveStateLoadResult:
	return SaveStateLoadResult.success(data, schema) if metadata_only else owner_ref.get_ref()._run_schema_migration_pipeline(data, schema)
