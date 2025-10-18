extends CharacterBody3D

# Network sync
@export var player_id: int = 0  # Which player owns this unit
@export var unit_id: int = 0    # Unique ID for this unit

# References
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var selection_indicator: MeshInstance3D = $SelectionIndicator
@onready var model: Node3D = $Model
@onready var animation_player: AnimationPlayer = $Model/worker/AnimationPlayer

# Movement
@export var move_speed: float = 5.0
var is_selected: bool = false
var current_animation: String = "idle"

# State
enum UnitState { IDLE, MOVING, CHOPPING }
var state: UnitState = UnitState.IDLE

func _ready():
	# Wait for first physics frame for NavigationServer to sync
	call_deferred("setup_agent")
	
	# Start with idle animation
	play_animation("Idle")
	
	# Hide selection indicator by default
	selection_indicator.visible = false

func setup_agent():
	# Wait for navigation map to be ready
	await get_tree().physics_frame
	
	navigation_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta):
	match state:
		UnitState.MOVING:
			process_movement(delta)
		UnitState.CHOPPING:
			# Will implement later
			pass
		UnitState.IDLE:
			if current_animation != "idle":
				play_animation("idle")

func process_movement(delta):
	if navigation_agent.is_navigation_finished():
		state = UnitState.IDLE
		velocity = Vector3.ZERO
		return
	
	var next_position = navigation_agent.get_next_path_position()
	var direction = (next_position - global_position).normalized()
	
	# Face movement direction
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 10.0)
	
	# Move using navigation agent avoidance
	var desired_velocity = direction * move_speed
	navigation_agent.set_velocity(desired_velocity)
	
	# Play walk animation
	if current_animation != "walk":
		play_animation("Walk")

func _on_velocity_computed(safe_velocity: Vector3):
	# This is called by NavigationAgent with collision-free velocity
	velocity = safe_velocity
	move_and_slide()

func move_to_position(target_position: Vector3):
	"""Command unit to move to a position"""
	navigation_agent.target_position = target_position
	state = UnitState.MOVING

func select():
	"""Select this unit"""
	is_selected = true
	selection_indicator.visible = true

func deselect():
	"""Deselect this unit"""
	is_selected = false
	selection_indicator.visible = false

func play_animation(anim_name: String):
	"""Play an animation if it exists"""
	if animation_player.has_animation(anim_name):
		current_animation = anim_name
		animation_player.play(anim_name)
	else:
		push_warning("Animation not found: ", anim_name)

func get_owner_id() -> int:
	"""Return which player owns this unit"""
	return player_id
