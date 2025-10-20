extends CharacterBody3D

# Network sync
@export var player_id: int = 0
@export var unit_id: int = 0

# References
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var selection_indicator: MeshInstance3D = $SelectionIndicator
@onready var model: Node3D = $Model

# Movement
@export var move_speed: float = 5.0
var is_selected: bool = false
var current_animation: String = "Idle"
var animation_player: AnimationPlayer = null

# State
enum UnitState { IDLE, MOVING, CHOPPING }
var state: UnitState = UnitState.IDLE

func _ready():
	print("\n=== WORKER UNIT READY ===")
	print("Worker position: ", global_position)
	
	# Try multiple methods to find AnimationPlayer
	animation_player = find_child("AnimationPlayer", true, false)
	
	if not animation_player:
		# Try getting it from the GLB node directly
		var glb_node = model.get_child(0) if model.get_child_count() > 0 else null
		if glb_node:
			print("Found GLB node: ", glb_node.name)
			animation_player = glb_node.find_child("AnimationPlayer", true, false)
	
	if animation_player:
		print("✓ AnimationPlayer found at: ", animation_player.get_path())
		print("  Available animations: ", animation_player.get_animation_list())
		print("  Current animation: ", animation_player.current_animation)
		print("  Is playing: ", animation_player.is_playing())
		
		# Try to play idle
		play_animation("Idle")
		
		# Double-check after trying to play
		await get_tree().create_timer(0.1).timeout
		print("  After play attempt - Is playing: ", animation_player.is_playing())
		print("  Current animation: ", animation_player.current_animation)
	else:
		push_error("✗ AnimationPlayer NOT found!")
		print("Model children:")
		for child in model.get_children():
			print("  - ", child.name, " (", child.get_class(), ")")
			if child.get_child_count() > 0:
				for subchild in child.get_children():
					print("    - ", subchild.name, " (", subchild.get_class(), ")")
	
	call_deferred("setup_agent")
	selection_indicator.visible = false
	print("=========================\n")

func setup_agent():
	await get_tree().physics_frame
	navigation_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta):
	match state:
		UnitState.MOVING:
			process_movement(delta)
		UnitState.IDLE:
			if animation_player and current_animation != "Idle":
				play_animation("Idle")

func process_movement(delta):
	if navigation_agent.is_navigation_finished():
		state = UnitState.IDLE
		velocity = Vector3.ZERO
		return
	
	var next_position = navigation_agent.get_next_path_position()
	var direction = (next_position - global_position).normalized()
	
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 10.0)
	
	var desired_velocity = direction * move_speed
	navigation_agent.set_velocity(desired_velocity)
	
	if animation_player and current_animation != "Walk":
		play_animation("Walk")

func _on_velocity_computed(safe_velocity: Vector3):
	velocity = safe_velocity
	move_and_slide()

func move_to_position(target_position: Vector3):
	navigation_agent.target_position = target_position
	state = UnitState.MOVING

func select():
	is_selected = true
	selection_indicator.visible = true

func deselect():
	is_selected = false
	selection_indicator.visible = false

func play_animation(anim_name: String):
	if not animation_player:
		push_warning("Cannot play animation - AnimationPlayer is null")
		return
	
	print("Attempting to play animation: ", anim_name)
	
	if animation_player.has_animation(anim_name):
		current_animation = anim_name
		animation_player.play(anim_name)
		print("  ✓ Playing: ", anim_name)
	else:
		push_warning("Animation '", anim_name, "' not found. Available: ", animation_player.get_animation_list())

func get_owner_id() -> int:
	return player_id
