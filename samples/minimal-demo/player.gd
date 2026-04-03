extends CharacterBody2D
## Demo player: movement + a saveable accent color (see main.gd for SaveManager keys).

@export var gold: int = 0
var accent: Color = Color(0.25, 0.55, 0.95)
const SPEED: float = 220.0


func set_accent(c: Color) -> void:
	accent = c
	queue_redraw()


func _physics_process(_delta: float) -> void:
	var input := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	velocity = input * SPEED
	move_and_slide()


func _draw() -> void:
	draw_rect(Rect2(Vector2(-14, -14), Vector2(28, 28)), accent)
