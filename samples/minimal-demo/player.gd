extends CharacterBody2D
## Demo stat persisted via SaveManager (see main.gd).

@export var gold: int = 0
const SPEED: float = 220.0


func _physics_process(_delta: float) -> void:
	var input := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	velocity = input * SPEED
	move_and_slide()


func _draw() -> void:
	draw_rect(Rect2(Vector2(-14, -14), Vector2(28, 28)), Color(0.25, 0.55, 0.95))
