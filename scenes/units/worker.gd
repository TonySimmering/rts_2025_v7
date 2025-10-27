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

# Command Queue System
var command_queue: Array[UnitCommand] = []
var current_command: UnitCommand = null

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

# Gathering
var target_resource: Node = null
var gather_timer: float = 0.0
const GATHER_INTERVAL: float = 2.0  # Gather every 2 seconds
const GATHER_RANGE: float = 2.5

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
	
	# Process current command or get next from queue
	if current_command == null and command_queue.size() > 0:
		current_command = command_queue.pop_front()
		_execute_command(current_command)
	
	match state:
		UnitState.MOVING:
			process_movement(delta)
		UnitState.GATHERING:
			process_gathering(delta)
		UnitState.IDLE:
			# Still apply gravity and movement even when idle
			move_and_slide()
			if animation_player and current_animation != "Idle":
				play_animation("Idle")

func process_movement(delta):
	if navigation_agent.is_navigation_finished():
		print("Navigation finished!")
		
		# Check if we reached a resource for gathering
		if current_command and current_command.type == UnitCommand.CommandType.GATHER:
			if target_resource and is_instance_valid(target_resource):
				var distance = global_position.distance_to(target_resource.global_position)
				if distance <= GATHER_RANGE:
					print("Reached resource, starting gathering")
					state = UnitState.GATHERING
					velocity = Vector3.ZERO
					target_resource.start_gathering(self)
					play_animation("Idle")  # TODO: Add gather animation
					return
		
		# Otherwise, command complete
		state = UnitState.IDLE
		velocity.x = 0
		velocity.z = 0
		
		# Apply formation facing direction
		if has_facing_target:
			rotation.y = target_facing_angle
			has_facing_target = false
		
		play_animation("Idle")
		current_command = null
		return
	
	# Improved stuck detection
	check_timer += delta
	if check_timer >= stuck_check_interval:
		check_timer = 0.0
		
		var distance_moved = global_position.distance_to(last_check_position)
		var distance_to_target = global_position.distance_to(navigation_agent.target_position)
		
		if distance_moved < stuck_distance_threshold and distance_to_target > 2.0:
			stuck_timer += stuck_check_interval
			
			if stuck_timer >= max_stuck_time:
				print("⚠ Unit stuck! Trying alternative path...")
				
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
	
	var desired_velocity = direction * move_speed
	navigation_agent.set_velocity(desired_velocity)
	
	if animation_player and current_animation != "Walk":
		play_animation("Walk")

func process_gathering(delta):
	"""Handle gathering state"""
	if not target_resource or not is_instance_valid(target_resource):
		print("Resource invalid, stopping gather")
		state = UnitState.IDLE
		current_command = null
		return
	
	# Check if still in range
	var distance = global_position.distance_to(target_resource.global_position)
	if distance > GATHER_RANGE:
		print("Too far from resource, moving closer")
		state = UnitState.MOVING
		navigation_agent.target_position = target_resource.global_position
		return
	
	# Face the resource
	var direction = (target_resource.global_position - global_position).normalized()
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
	
	# Gather periodically
	gather_timer += delta
	if gather_timer >= GATHER_INTERVAL:
		gather_timer = 0.0
		
		# Only authority can gather (server)
		if multiplayer.is_server():
			var result = target_resource.gather(self)
			if result.success:
				# Award resources to player
				ResourceManager.add_resource(player_id, result.resource_type, result.amount)
			else:
				# Resource depleted or can't gather
				print("Cannot gather, stopping")
				target_resource.stop_gathering(self)
				state = UnitState.IDLE
				current_command = null
				target_resource = null

# Command Queue System
func queue_command(command: UnitCommand, append: bool = false):
	"""Queue a command for this unit"""
	if not is_multiplayer_authority():
		return
	
	queue_command_rpc.rpc(command.to_dict(), append)

@rpc("any_peer", "call_local", "reliable")
func queue_command_rpc(command_data: Dictionary, append: bool):
	"""Receive and queue command on all clients"""
	var command = UnitCommand.from_dict(command_data)
	
	if append:
		command_queue.append(command)
		print("📋 Queued command: ", command, " (queue size: ", command_queue.size(), ")")
	else:
		# Stop current gathering if switching commands
		if state == UnitState.GATHERING and target_resource:
			target_resource.stop_gathering(self)
			target_resource = null
		
		command_queue.clear()
		current_command = null
		command_queue.append(command)
		print("📋 New command: ", command)

func _execute_command(command: UnitCommand):
	"""Execute a command from the queue"""
	match command.type:
		UnitCommand.CommandType.MOVE:
			_execute_move_command(command)
		UnitCommand.CommandType.GATHER:
			_execute_gather_command(command)
		UnitCommand.CommandType.BUILD:
			print("Build command not yet implemented")
			current_command = null
		UnitCommand.CommandType.ATTACK:
			print("Attack command not yet implemented")
			current_command = null
		UnitCommand.CommandType.PATROL:
			print("Patrol command not yet implemented")
			current_command = null

func _execute_move_command(command: UnitCommand):
	"""Execute a move command"""
	var target_position = command.target_position
	var facing_angle = command.facing_angle
	
	# Validate path exists
	var nav_map = get_world_3d().navigation_map
	var path = NavigationServer3D.map_get_path(
		nav_map,
		global_position,
		target_position,
		true
	)
	
	if path.size() < 2:
		print("✗ NO VALID PATH from ", global_position, " to ", target_position)
		current_command = null
		return
	
	print("✓ Valid path with ", path.size(), " waypoints")
	
	navigation_agent.target_position = target_position
	
	target_facing_angle = facing_angle
	has_facing_target = true
	
	stuck_timer = 0.0
	check_timer = 0.0
	last_check_position = global_position
	
	state = UnitState.MOVING

func _execute_gather_command(command: UnitCommand):
	"""Execute a gather command"""
	target_resource = command.target_entity
	
	if not target_resource or not is_instance_valid(target_resource):
		print("✗ Invalid resource target")
		current_command = null
		return
	
	if not target_resource.can_gather():
		print("✗ Resource depleted")
		current_command = null
		return
	
	print("✓ Moving to gather from ", target_resource.get_resource_type_string())
	
	# Move to resource
	navigation_agent.target_position = target_resource.global_position
	state = UnitState.MOVING

func resource_depleted():
	"""Called when the resource we're gathering from depletes"""
	if state == UnitState.GATHERING:
		print("Resource depleted while gathering")
		state = UnitState.IDLE
		current_command = null
		target_resource = null

func get_command_queue_size() -> int:
	"""Get the number of queued commands"""
	return command_queue.size() + (1 if current_command != null else 0)

# Legacy support
func move_to_position(target_position: Vector3, facing_angle: float = 0.0):
	"""Legacy move function"""
	if not is_multiplayer_authority():
		return
	
	var command = UnitCommand.new(UnitCommand.CommandType.MOVE)
	command.target_position = target_position
	command.facing_angle = facing_angle
	queue_command(command, false)

@rpc("any_peer", "call_local", "reliable")
func move_to_position_rpc(target_position: Vector3, facing_angle: float = 0.0):
	"""Legacy RPC"""
	var command = UnitCommand.new(UnitCommand.CommandType.MOVE)
	command.target_position = target_position
	command.facing_angle = facing_angle
	_execute_command(command)

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
