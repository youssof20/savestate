@tool
extends Window
var get_manager: Callable
var output: TextEdit
var root_field: LineEdit
var schema_field: LineEdit
var report: PackedStringArray = []

func _ready() -> void:
	hide()
	title = "SaveState · Setup"
	size = Vector2i(740, 580)
	min_size = Vector2i(450, 380)
	transient = true
	close_requested.connect(hide)
	var background := PanelContainer.new()
	background.theme = EditorInterface.get_editor_theme()
	var panel := StyleBoxFlat.new()
	panel.bg_color = EditorInterface.get_editor_settings().get_setting("interface/theme/base_color")
	panel.set_corner_radius_all(5)
	background.add_theme_stylebox_override("panel", panel)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 16)
	background.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	var label := Label.new()
	label.text = "Project setup"
	label.add_theme_font_size_override("font_size", 20)
	body.add_child(label)
	root_field = field(body, "Save folder", str(ProjectSettings.get_setting("savestate/save_root", "user://savestate")))
	schema_field = field(body, "Shared schema setup script (optional)", str(ProjectSettings.get_setting("savestate/schema_setup_script", "")))
	var actions := HFlowContainer.new()
	body.add_child(actions)
	button(actions, "Apply settings…", apply_settings)
	button(actions, "Add persistence to selection…", preview_components)
	button(actions, "Validate open scene", validate_open)
	var project_check := button(actions, "Validate project scenes", validate_project)
	project_check.visible = get_manager.call().supports_profiles()
	button(actions, "Test storage", test_storage)
	button(actions, "Open save menu scene", func():
		var manager: SaveManagerBase = get_manager.call()
		EditorInterface.open_scene_from_path("res://addons/savestate_pro/templates/save_menu_pro.tscn" if manager.supports_profiles() else "res://addons/savestate/templates/save_menu_lite.tscn")
	)
	output = TextEdit.new()
	output.editable = false
	output.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(output)
	output.text = "Select nodes and add persistence, then choose their saved properties. Run the game and save to see it in the dock.\n\nThe optional schema script registers keys and migrations through configure(manager)."
	if get_manager.call().supports_profiles(): output.text += "\n\nFor managed worlds, register scenes and prefabs before starting the session."

func field(parent: Node, title_: String, text: String) -> LineEdit:
	var label := Label.new()
	label.text = title_
	parent.add_child(label)
	var input := LineEdit.new()
	input.text = text
	parent.add_child(input)
	return input

func button(parent: Node, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.pressed.connect(action)
	parent.add_child(item)
	return item

func confirm(text: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Apply setup changes?"
	dialog.dialog_text = text
	add_child(dialog)
	dialog.confirmed.connect(func(): action.call(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func apply_settings() -> void:
	var path := root_field.text.strip_edges()
	var schema := schema_field.text.strip_edges()
	if not path.begins_with("user://") or ".." in path:
		output.text = "Use a folder inside user:// for game saves."; return
	if schema != "" and (not schema.begins_with("res://") or not schema.ends_with(".gd") or not ResourceLoader.exists(schema)):
		output.text = "Select an existing project .gd script, or leave the schema field empty."; return
	confirm("Save folder: " + path + "\nSchema setup: " + ("None" if schema == "" else schema) + "\n\nExisting saves will not be moved. Restart the game after changing these settings.", func():
		ProjectSettings.set_setting("savestate/save_root", path)
		ProjectSettings.set_setting("savestate/schema_setup_script", schema)
		var error := ProjectSettings.save()
		var manager: SaveManagerBase = get_manager.call()
		manager.save_root = path
		output.text = "Settings saved. Reload the editor to register updated schema callbacks." if error == OK else "Could not save Project Settings."
	)

func preview_components() -> void:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	if nodes.is_empty(): output.text = "Select one or more nodes in the Scene tree first."; return
	var manager: SaveManagerBase = get_manager.call()
	var pro := manager.supports_profiles()
	var text := "Add %s to:\n" % ("a persistent world component" if pro else "a save component")
	for node in nodes: text += "• " + str(node.name) + "\n"
	text += "\nAvailable position and health fields will be selected. Scene edits can be undone."
	confirm(text, func(): add_components(nodes, pro))

func add_components(nodes: Array, pro: bool) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null: output.text = "Open a scene first."; return
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Add SaveState persistence", UndoRedo.MERGE_DISABLE, root)
	var added := 0
	for node in nodes:
		if node != root and not root.is_ancestor_of(node): continue
		var script_path := "res://addons/savestate_pro/world/entity.gd" if pro else "res://addons/savestate/save_component.gd"
		var exists := false
		for child in node.get_children():
			if child.get_script() != null and child.get_script().resource_path == script_path: exists = true
		if exists: continue
		var component: Node = load(script_path).new()
		component.name = "Persistence"
		var names: Array = node.get_property_list().map(func(item): return str(item.name))
		var chosen: PackedStringArray = []
		for name_ in ["position", "health"]:
			if name_ in names: chosen.append(name_)
		if pro:
			component.placement_id = Crypto.new().generate_random_bytes(16).hex_encode()
			component.additions = chosen
		else:
			component.storage_key = StringName(Crypto.new().generate_random_bytes(16).hex_encode())
			component.tracked_properties = chosen
		undo.add_do_method(node, "add_child", component, true)
		undo.add_do_method(component, "set_owner", root)
		undo.add_undo_method(node, "remove_child", component)
		undo.add_do_reference(component)
		added += 1
	undo.commit_action()
	output.text = "Added %d components. Select Persistence to choose saved fields. Save the scene when ready." % added

func validate_open() -> void:
	report.clear()
	var root := EditorInterface.get_edited_scene_root()
	if root == null: output.text = "Open a scene to validate it."; return
	validate_scene(root, root.scene_file_path)
	output.text = "\n".join(report)

func validate_scene(root: Node, path: String) -> void:
	var manager: SaveManagerBase = get_manager.call()
	if not manager.supports_profiles():
		var keys := {}
		for node in [root] + root.find_children("*", "Node", true, false):
			if node.get_script() == null or node.get_script().resource_path != "res://addons/savestate/save_component.gd": continue
			var key := str(node.get("storage_key"))
			if key == "" or keys.has(key): report.append(path + " / " + str(root.get_path_to(node)) + ": missing or duplicate storage key. Assign a unique key.")
			keys[key] = true
		report.append("%s: %d Lite components checked." % [path, keys.size()])
		return
	var world: RefCounted = load("res://addons/savestate_pro/world/world.gd").new(manager, root, {}, {}, "")
	var indexed: SaveStateResult = world.index(root)
	if not indexed.ok: report.append(path + " / " + indexed.data_path + ": " + indexed.message); return
	var data := {}
	for id in indexed.data:
		var entity: Node = indexed.data[id]
		var fields: Dictionary = entity.selection().data.fields
		for key in fields:
			var budget := {"count": 0, "ok": true}
			var value: Variant = entity.plain_value(entity.target().get(fields[key]), budget)
			if not budget.ok or SaveStateGenerationCodec.encode({"value": value}).error != OK:
				report.append(path + " / " + id + "/" + key + ": unsupported value. Select plain data or add a migration.")
			else: data[id + "/" + key] = value
	var encoded := SaveStateGenerationCodec.encode(data)
	var decoded := SaveStateGenerationCodec.decode(encoded.bytes) if encoded.error == OK else {"error": encoded.error}
	report.append("%s: %d entities · selected-data codec round trip %s" % [path, indexed.data.size(), "passed" if decoded.error == OK else "failed"])

func validate_project() -> void:
	report.clear()
	var manager: SaveManagerBase = get_manager.call()
	if not manager.supports_profiles(): output.text = "Project-wide scene checks require Pro. Validate open scene is available in Lite."; return
	scan_scenes("res://", 0)
	output.text = "\n".join(report) if not report.is_empty() else "No project scenes found."

func scan_scenes(path: String, depth: int) -> void:
	if depth > 12 or report.size() >= 256: return
	var dir := DirAccess.open(path)
	if dir == null: return
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			var packed: PackedScene = load(path.path_join(file))
			if packed == null: report.append(path.path_join(file) + ": cannot load scene."); continue
			var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			validate_scene(root, path.path_join(file))
			root.free()
	for folder in dir.get_directories():
		if not folder.begins_with(".") and folder not in ["addons", "Tests", "tests"]: scan_scenes(path.path_join(folder), depth + 1)

func test_storage() -> void:
	var manager: SaveManagerBase = get_manager.call()
	var scratch: SaveManagerBase = manager.get_script().new()
	scratch.save_root = "user://savestate-editor-tests/" + Crypto.new().generate_random_bytes(8).hex_encode()
	scratch._ready()
	var saved := scratch.save_generation_sync(&"probe", {"probe": Vector2(1, 2), "empty": {}})
	var loaded := scratch.load_generation_sync(&"probe") if saved.ok else saved
	output.text = "Scratch save and read passed.\n" + ProjectSettings.globalize_path(scratch.save_root) if loaded.ok and loaded.data.get("probe") == Vector2(1, 2) else loaded.message
	scratch.free()
