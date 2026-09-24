extends SceneTree

var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		printerr("FAIL: " + label)

func run() -> void:
	var scene = load("res://samples/minimal-demo/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.ready_to_play, "demo starts a session: " + scene.status.text)
	if OS.get_cmdline_user_args()[0] == "save":
		scene.player.gold = 42
		scene.xp = 15
		scene.player.position = Vector2(700, 250)
		await scene.save_state()
		check(scene.status.text == "Saved", "demo saves")
		scene.player.gold = 99
		await scene.save_state(&"checkpoint")
		check(scene.status.text == "Saved", "named checkpoint saves")
	else:
		check(scene.player.gold == 42 and scene.xp == 15, "restart restores active save")
		check(scene.player.position.is_equal_approx(Vector2(700, 250)), "restart restores position")
		scene.load_state(&"checkpoint")
		check(scene.player.gold == 99, "checkpoint loads")
	var manager = root.get_node("SaveManager")
	check(not manager.supports_profiles(), "Lite capability")
	check(manager.list_slots().data.entries.size() == 2, "two saves catalogued")
	check(manager.list_slot_history().ok, "history is readable")
	scene.queue_free()
	await process_frame
	quit(1 if failed else 0)
