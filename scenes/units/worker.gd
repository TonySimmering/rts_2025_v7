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
@export var gravity: float = 20.0
@export var stuck_check_interval: float = 2.0
@export var stuck_distance_threshold: float = 1.0
@export var max_stuck_time: float = 6.0

var is_selected: bool = false
var current_animation: String = "Idle"
var animation_player: AnimationPlayer = null

# Formation facing
var target_facing_angle: float = 0.0
var has_facing_target: bool = false

# Stuck detection
var last_check_position: Vector3 = Vector3.ZERO
var stuck_timer: float = 0.0
var check_timer: float = 0.0

# State
enum UnitState { IDLE, MOVING, GATHERING }
var state: UnitState = UnitState.IDLE

func _ready():
	add_to_group("units")
	
	# Set multiplayer authority based on player_id
	set_multiplayer_authority(player_id)
	
	print("\n=== WORKER UNIT READY ===")
	print("Worker position: ", global_position)
	print("Player ID: ", player_id, " | Authority: ", get_multiplayer_authority())
	
	animation_player = find_child("AnimationPlayer", true, false)
	
	if not animation_player:
		var glb_node = model.get_child(0) if model.get_child_count() > 0 else null
		if glb_node:
			animation_player = glb_node.find_child("AnimationPlayer", true, false)
	
	if animation_player:
		print("✓ AnimationPlayer found")
		play_animation("Idle")
	else:
		push_error("✗ AnimationPlayer NOT found!")
	
	call_deferred("setup_agent")
	selection_indicator.visible = false
	print("=========================\n")

func setup_agent():
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Configure avoidance
	navigation_agent.avoidance_enabled = true
	navigation_agent.radius = 0.5
	navigation_agent.max_neighbors = 10
	navigation_agent.time_horizon_agents = 1.0
	navigation_agent.max_speed = move_speed
	
	# Connect avoidance signal
	navigation_agent.velocity_computed.connect(_on_velocity_computed)
	
	print("NavigationAgent setup:")
	print("  Map RID valid: ", navigation_agent.get_navigation_map().is_valid())
	print("  Agent avoidance enabled: ", navigation_agent.avoidance_enabled)

func _on_velocity_computed(safe_velocity: Vector3):
	"""Called when avoidance calculation completes"""
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()

func _physics_process(delta):
	# Apply gravity when not on floor
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	match state:
		UnitState.MOVING:
			process_movement(delta)
		UnitState.IDLE:
			# Still apply gravity and movement even when idle
			move_and_slide()
			if animation_player and current_animation != "Idle":
				play_animation("Idle")

func process_movement(delta):
	if navigation_agent.is_navigation_finished():
		print("Navigation finished! Stopping.")
		state = UnitState.IDLE
		velocity.x = 0
		velocity.z = 0
		
		# Apply formation facing direction
		if has_facing_target:
			rotation.y = target_facing_angle
			has_facing_target = false
			print("Applied formation facing: ", rad_to_deg(target_facing_angle), " degrees")
		
		play_animation("Idle")
		return
	
	# Improved stuck detection
	check_timer += delta
	if check_timer >= stuck_check_interval:
		check_timer = 0.0
		
		var distance_moved = global_position.distance_to(last_check_position)
		var distance_to_target = global_position.distance_to(navigation_agent.target_position)
		
		# Consider stuck if: not moving AND still far from target
		if distance_moved < stuck_distance_threshold and distance_to_target > 2.0:
			stuck_timer += stuck_check_interval
			
			if stuck_timer >= max_stuck_time:
				print("⚠ Unit stuck! Trying alternative path...")
				
				# Try finding path to a point near the target
				var nav_map = get_world_3d().navigation_map
				var nearby_target = navigation_agent.target_position + Vector3(
					randf_range(-3, 3),
					0,
					randf_range(-3, 3)
				)
				var closest = NavigationServer3D.map_get_closest_point(nav_map, nearby_target)
				
				print("  Retargeting to nearby position: ", closest)
				navigation_agent.target_position = closest
				stuck_timer = 0.0
		else:
			stuck_timer = 0.0
		
		last_check_position = global_position
	
	var next_position = navigation_agent.get_next_path_position()
	var direction = (next_position - global_position).normalized()
	
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 10.0)
	
	# Use set_velocity for avoidance instead of direct movement
	var desired_velocity = direction * move_speed
	navigation_agent.set_velocity(desired_velocity)
	
	if animation_player and current_animation != "Walk":
		play_animation("Walk")

func move_to_position(target_position: Vector3, facing_angle: float = 0.0):
	# Only the owner can issue move commands
	if not is_multiplayer_authority():
		return
	
	# Send move command to all clients with facing angle
	move_to_position_rpc.rpc(target_position, facing_angle)

@rpc("any_peer", "call_local", "reliable")
func move_to_position_rpc(target_position: Vector3, facing_angle: float = 0.0):
	"""Execute move command on all clients with path validation"""
	
	# Validate path exists before moving
	var nav_map = get_world_3d().navigation_map
	var path = NavigationServer3D.map_get_path(
		nav_map,
		global_position,
		target_position,
		true  # optimize
	)
	
	if path.size() < 2:
		print("✗ NO VALID PATH from ", global_position, " to ", target_position)
		return  # Don't move if no path
	
	print("✓ Valid path with ", path.size(), " waypoints")
	
	navigation_agent.target_position = target_position
	
	# Store the formation facing angle
	target_facing_angle = facing_angle
	has_facing_target = true
	
	# Reset stuck detection
	stuck_timer = 0.0
	check_timer = 0.0
	last_check_position = global_position
	
	state = UnitState.MOVING

func select():
	is_selected = true
	selection_indicator.visible = true

func deselect():
	is_selected = false
	selection_indicator.visible = false

func play_animation(anim_name: String):
	if not animation_player:
		return
	
	if animation_player.has_animation(anim_name):
		current_animation = anim_name
		animation_player.play(anim_name)

func get_owner_id() -> int:
	return player_id
