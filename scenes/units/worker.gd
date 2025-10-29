extends CharacterBody3D

# Network sync
@export var player_id: int = 0
@export var unit_id: int = 0

# References
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var selection_indicator: MeshInstance3D = $SelectionIndicator
@onready var model: Node3D = $Model

# Movement
@export var move_speed: float = 3
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
enum UnitState { IDLE, MOVING, GATHERING, RETURNING, DEPOSITING }
var state: UnitState = UnitState.IDLE

# Gathering
var target_resource: Node = null
var gather_timer: float = 0.0
const GATHER_INTERVAL: float = 2.0
const GATHER_RANGE: float = 4.0

# Resource Carrying
var carrying_resources: Dictionary = {}  # {resource_type: amount}
var max_carry_capacity: int = 20  # Max resources per trip
var current_dropoff: Node = null  # Town Center reference
const DROPOFF_SEARCH_INTERVAL: float = 5.0
var dropoff_search_timer: float = 0.0

func _ready():
	add_to_group("units")
	add_to_group("player_%d_units" % player_id)
	
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
	
	if not is_instance_valid(navigation_agent):
		push_error("NavigationAgent is invalid on setup!")
		return
	
	navigation_agent.avoidance_enabled = true
	navigation_agent.radius = 0.5
	navigation_agent.max_neighbors = 10
	navigation_agent.time_horizon_agents = 1.0
	navigation_agent.max_speed = move_speed
	
	navigation_agent.velocity_computed.connect(_on_velocity_computed)
	
	print("NavigationAgent setup:")
	print("  Map RID valid: ", navigation_agent.get_navigation_map().is_valid())
	print("  Agent avoidance enabled: ", navigation_agent.avoidance_enabled)

func _on_velocity_computed(safe_velocity: Vector3):
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Process dropoff search
	if multiplayer.is_server():
		dropoff_search_timer += delta
		if dropoff_search_timer >= DROPOFF_SEARCH_INTERVAL:
			dropoff_search_timer = 0.0
			if not current_dropoff or not is_instance_valid(current_dropoff):
				find_nearest_dropoff()
	
	# Process current command or get next from queue
	if current_command == null and command_queue.size() > 0:
		current_command = command_queue.pop_front()
		_execute_command(current_command)
	
	match state:
		UnitState.MOVING:
			process_movement(delta)
		UnitState.GATHERING:
			process_gathering(delta)
		UnitState.RETURNING:
			process_returning(delta)
		UnitState.DEPOSITING:
			process_depositing(delta)
		UnitState.IDLE:
			move_and_slide()
			if animation_player and current_animation != "Idle":
				play_animation("Idle")

# ============ RESOURCE CARRYING SYSTEM ============

func get_carried_amount() -> int:
	"""Get total amount of resources being carried"""
	var total = 0
	for amount in carrying_resources.values():
		total += amount
	return total

func is_carrying_resources() -> bool:
	return get_carried_amount() > 0

func has_carry_space() -> bool:
	return get_carried_amount() < max_carry_capacity

func add_carried_resource(resource_type: String, amount: int):
	"""Add resources to carry inventory"""
	if not carrying_resources.has(resource_type):
		carrying_resources[resource_type] = 0
	
	carrying_resources[resource_type] += amount
	print("Worker carrying: ", carrying_resources)

func clear_carried_resources():
	"""Clear all carried resources"""
	carrying_resources.clear()

func find_nearest_dropoff():
	"""Find nearest building that accepts dropoffs (Town Center)"""
	var dropoff_buildings = get_tree().get_nodes_in_group("player_%d_buildings" % player_id)
	
	var nearest: Node = null
	var nearest_dist = INF
	
	for building in dropoff_buildings:
		if not is_instance_valid(building):
			continue
		
		if building.has_method("can_dropoff_resources") and building.can_dropoff_resources():
			var dist = global_position.distance_to(building.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = building
	
	if nearest:
		current_dropoff = nearest
		print("Found dropoff: ", current_dropoff.building_name, " at ", nearest_dist, " units away")
	else:
		print("⚠ No dropoff building found for player ", player_id)

# ============ STATE PROCESSING ============

func process_movement(delta):
	if navigation_agent.is_navigation_finished():
		print("Navigation finished!")
		
		# --- CRITICAL FIX: GATHERING LOGIC ---
		if current_command and current_command.type == UnitCommand.CommandType.GATHER:
			if target_resource and is_instance_valid(target_resource):
				var distance = global_position.distance_to(target_resource.global_position)
				if distance <= GATHER_RANGE:
					# Reached resource, start gathering
					print("Reached resource, starting gathering")
					state = UnitState.GATHERING
					velocity = Vector3.ZERO
					target_resource.start_gathering(self)
					play_animation("Idle")
					return
				else:
					# FIX: Nav finished but not in range. 
					# Force state to GATHERING, which will check range and re-path.
					print("Nav finished but not in GATHER_RANGE. Forcing GATHER state.")
					state = UnitState.GATHERING
					velocity = Vector3.ZERO
					play_animation("Idle")
					return
			else:
				# Target resource became invalid during move
				print("Target resource invalid, stopping command.")
		
		# --- END OF GATHERING FIX ---

		# Default behavior (for MOVE commands or failed GATHER)
		state = UnitState.IDLE
		velocity.x = 0
		velocity.z = 0
		
		if has_facing_target:
			rotation.y = target_facing_angle
			has_facing_target = false
		
		play_animation("Idle")
		current_command = null
		return
	
	# Stuck detection
	check_timer += delta
	if check_timer >= stuck_check_interval:
		check_timer = 0.0
		
		var distance_moved = global_position.distance_to(last_check_position)
		var distance_to_target = global_position.distance_to(navigation_agent.target_position)
		
		if distance_moved < stuck_distance_threshold and distance_to_target > 2.0:
			stuck_timer += stuck_check_interval
			
			# --- CRITICAL FIX: STUCK LOGIC ---
			if stuck_timer >= max_stuck_time:
				print("⚠ Unit stuck! Trying alternative nearby point...")
				
				var nav_map = get_world_3d().navigation_map
				# Find a point near the *current* position, not the final target
				var nearby_target = global_position + Vector3(
					randf_range(-4, 4),
					0,
					randf_range(-4, 4)
				)
				var closest_point = NavigationServer3D.map_get_closest_point(nav_map, nearby_target)
				
				# Create a temporary move command to this point
				var temp_move = UnitCommand.new(UnitCommand.CommandType.MOVE)
				temp_move.target_position = closest_point
				
				# Insert this command *before* the current one
				if current_command:
					command_queue.push_front(current_command)
				current_command = temp_move
				
				print("  Inserting temporary move to: ", closest_point)
				_execute_command(current_command) # Execute the new temp move
				stuck_timer = 0.0
				return # Exit process_movement for this frame
			# --- END OF STUCK FIX ---
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
	
	# Check if inventory full
	if not has_carry_space():
		print("Inventory full! Returning to dropoff")
		start_returning_to_dropoff()
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
		
		if multiplayer.is_server():
			var result = target_resource.gather(self)
			if result.success:
				# Add to carrying inventory (don't award yet)
				add_carried_resource(result.resource_type, result.amount)
				
				# If full or resource depleted, return to dropoff
				if not has_carry_space() or not target_resource.can_gather():
					start_returning_to_dropoff()
			else:
				print("Cannot gather, resource depleted")
				target_resource.stop_gathering(self)
				start_returning_to_dropoff()

func start_returning_to_dropoff():
	"""Begin returning to Town Center with resources"""
	if not is_carrying_resources():
		state = UnitState.IDLE
		current_command = null
		target_resource = null
		return
	
	if not current_dropoff or not is_instance_valid(current_dropoff):
		find_nearest_dropoff()
	
	if not current_dropoff:
		print("⚠ No dropoff building! Resources lost")
		clear_carried_resources()
		state = UnitState.IDLE
		current_command = null
		return
	
	print("Returning to ", current_dropoff.building_name, " with ", get_carried_amount(), " resources")
	state = UnitState.RETURNING
	navigation_agent.target_position = current_dropoff.get_dropoff_position()
	play_animation("Walk")

func process_returning(delta):
	"""Handle returning to dropoff"""
	if not current_dropoff or not is_instance_valid(current_dropoff):
		print("⚠ Dropoff lost! Finding new one")
		find_nearest_dropoff()
		if not current_dropoff:
			state = UnitState.IDLE
			current_command = null
			return
	
	# Check if in dropoff range
	if current_dropoff.is_in_dropoff_range(global_position):
		state = UnitState.DEPOSITING
		velocity = Vector3.ZERO
		play_animation("Idle")
		return
	
	# Continue moving
	if navigation_agent.is_navigation_finished():
		print("⚠ Reached dropoff position but not in range")
		state = UnitState.DEPOSITING
		return
	
	var next_position = navigation_agent.get_next_path_position()
	var direction = (next_position - global_position).normalized()
	
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 10.0)
	
	var desired_velocity = direction * move_speed
	navigation_agent.set_velocity(desired_velocity)

func process_depositing(delta):
	"""Handle resource dropoff"""
	if not current_dropoff or not is_instance_valid(current_dropoff):
		state = UnitState.IDLE
		return
	
	# Face dropoff
	var direction = (current_dropoff.global_position - global_position).normalized()
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
	
	# Deposit (server only)
	if multiplayer.is_server():
		if current_dropoff.accept_resources(self, carrying_resources):
			clear_carried_resources()
			
			# Return to gather if resource still valid
			if target_resource and is_instance_valid(target_resource) and target_resource.can_gather():
				print("Dropoff complete, returning to resource")
				state = UnitState.MOVING
				navigation_agent.target_position = target_resource.global_position
			else:
				print("Dropoff complete, going idle")
				state = UnitState.IDLE
				current_command = null
				target_resource = null

# ============ COMMAND SYSTEM ============

func queue_command(command: UnitCommand, append: bool = false):
	if not is_multiplayer_authority():
		return
	
	queue_command_rpc.rpc(command.to_dict(), append)

@rpc("any_peer", "call_local", "reliable")
func queue_command_rpc(command_data: Dictionary, append: bool):
	var command = UnitCommand.from_dict(command_data)
	
	# --- CRITICAL FIX: Resolve NodePath to Node ---
	if command.target_path:
		command.target_entity = get_node_or_null(command.target_path)
		if not is_instance_valid(command.target_entity):
			print("✗ Failed to find target entity from path: ", command.target_path)
	# --- END OF FIX ---
	
	if append:
		command_queue.append(command)
		print("📋 Queued command: ", command, " (queue size: ", command_queue.size(), ")")
	else:
		if state == UnitState.GATHERING and target_resource:
			target_resource.stop_gathering(self)
			target_resource = null
		
		command_queue.clear()
		current_command = null
		command_queue.append(command)
		print("📋 New command: ", command)

func _execute_command(command: UnitCommand):
	if not command:
		return
		
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
	var target_position = command.target_position
	var facing_angle = command.facing_angle
	
	var nav_map = get_world_3d().navigation_map
	if not nav_map.is_valid():
		push_error("Cannot execute move: Invalid navigation map!")
		current_command = null
		return
		
	var path = NavigationServer3D.map_get_path(
		nav_map,
		global_position,
		target_position,
		true
	)
	
	if path.size() < 2:
		# Try to find closest valid point
		var closest_point = NavigationServer3D.map_get_closest_point(nav_map, target_position)
		path = NavigationServer3D.map_get_path(nav_map, global_position, closest_point, true)
		
		if path.size() < 2:
			print("✗ NO VALID PATH from ", global_position, " to ", target_position)
			current_command = null
			return
		else:
			print("✓ Valid path found to closest point: ", closest_point)
			target_position = closest_point
	else:
		print("✓ Valid path with ", path.size(), " waypoints")
	
	navigation_agent.target_position = target_position
	
	target_facing_angle = facing_angle
	has_facing_target = true
	
	stuck_timer = 0.0
	check_timer = 0.0
	last_check_position = global_position
	
	state = UnitState.MOVING

func _execute_gather_command(command: UnitCommand):
	target_resource = command.target_entity
	
	if not target_resource or not is_instance_valid(target_resource):
		print("✗ Invalid resource target for GATHER")
		current_command = null
		return
	
	if not target_resource.has_method("can_gather") or not target_resource.can_gather():
		print("✗ Resource depleted or invalid")
		current_command = null
		return
	
	print("✓ Moving to gather from ", target_resource.get_resource_type_string())
	
	# Ensure we have a dropoff building
	if not current_dropoff or not is_instance_valid(current_dropoff):
		find_nearest_dropoff()
	
	# Get a position near the resource
	var target_pos = target_resource.global_position
	var nav_map = get_world_3d().navigation_map
	if not nav_map.is_valid():
		push_error("Cannot execute gather: Invalid navigation map!")
		current_command = null
		return
		
	var closest_point = NavigationServer3D.map_get_closest_point(nav_map, target_pos)
	
	navigation_agent.target_position = closest_point
	state = UnitState.MOVING
	
	stuck_timer = 0.0
	check_timer = 0.0
	last_check_position = global_position

func resource_depleted():
	if state == UnitState.GATHERING:
		print("Resource depleted while gathering")
		if is_carrying_resources():
			start_returning_to_dropoff()
		else:
			state = UnitState.IDLE
			current_command = null
			target_resource = null

func get_command_queue_size() -> int:
	return command_queue.size() + (1 if current_command != null else 0)

# Legacy support
func move_to_position(target_position: Vector3, facing_angle: float = 0.0):
	if not is_multiplayer_authority():
		return
	
	var command = UnitCommand.new(UnitCommand.CommandType.MOVE)
	command.target_position = target_position
	command.facing_angle = facing_angle
	queue_command(command, false)

@rpc("any_peer", "call_local", "reliable")
func move_to_position_rpc(target_position: Vector3, facing_angle: float = 0.0):
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

# --- NEW FUNCTION ---
func update_navigation_map(new_map_rid: RID):
	"""
	Called by game.gd after the final navmesh bake to ensure the agent
	is using the latest navigation map.
	"""
	if is_instance_valid(navigation_agent):
		if new_map_rid.is_valid():
			navigation_agent.set_navigation_map(new_map_rid)
			print("Updated navigation map for worker: ", name, " with RID: ", new_map_rid)
		else:
			push_error("Attempted to update navmap with invalid RID for worker: ", name)
	else:
		push_error("Cannot update navmap: NavigationAgent is invalid for worker: ", name)
