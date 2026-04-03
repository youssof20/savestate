extends RefCounted
class_name SaveStateUnixDisplay
## Shared formatting for [method FileAccess.get_modified_time] (and similar) Unix seconds in UI.
## Godot's [method Time.get_datetime_string_from_unix_time] second argument is [code]use_space[/code]
## (separator between date and time), not a UTC flag — see official [Time] docs.


## Returns empty string when [param unix_sec] is less than or equal to 0.
static func format_modified_time(unix_sec: int, use_space_separator: bool = true) -> String:
	if unix_sec <= 0:
		return ""
	return Time.get_datetime_string_from_unix_time(unix_sec, use_space_separator)
