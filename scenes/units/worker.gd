extends CharacterBody3D

# Network sync
@export var player_id: int = 0
@export var unit_id: int = 0

const FlowField := preload("res://scripts/flow_field.gd")

# References
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var selection_indicator: MeshInstance3D = $SelectionIndicator
@onready var model: Node3D = $Model

# Movement
@export var move_speed: float = 3
@export var gravity: float = 20.0
@export var stuck_check_interval: float = 0.5  # Check more frequently
@export var stuck_distance_threshold: float = 0.5  # More sensitive detection
@export var max_stuck_time: float = 2.0  # Faster recovery
@export var path_recalc_interval: float = 2.0  # Periodic path updates

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
var path_recalc_timer: float = 0.0
var stuck_recovery_attempts: int = 0
const MAX_RECOVERY_ATTEMPTS: int = 3

# State
enum UnitState { IDLE, MOVING, GATHERING, RETURNING, DEPOSITING, BUILDING }
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

# Building/Construction
var target_construction_site: Node = null
const BUILD_RANGE: float = 5.0

# Flow field navigation
var flow_field_active: bool = false
var flow_field_data: Dictionary = {}
var flow_field_goal: Vector3 = Vector3.ZERO

func _ready():
	add_to_group("units")
	add_to_group("worker")
	add_to_group("player_%d_units" % player_id)
	
        set_multiplayer_authority(1)
	
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

	navigation_agent.avoidance_enabled = true
	navigation_agent.radius = 0.5
	navigation_agent.max_neighbors = 10
	navigation_agent.time_horizon_agents = 1.0
	navigation_agent.time_horizon_obstacles = 1.5  # More time to avoid obstacles
	navigation_agent.max_speed = move_speed

	# Configure avoidance layers to avoid buildings and resources (layer 1)
	navigation_agent.set_avoidance_layer_value(2, true)  # Units are on layer 2
	navigation_agent.set_avoidance_mask_value(1, true)   # Avoid layer 1 (buildings/resources)
	navigation_agent.set_avoidance_mask_value(2, true)   # Avoid layer 2 (other units)

	navigation_agent.velocity_computed.connect(_on_velocity_computed)

	print("NavigationAgent setup:")
	print("  Map RID valid: ", navigation_agent.get_navigation_map().is_valid())
	print("  Agent avoidance enabled: ", navigation_agent.avoidance_enabled)
	print("  Avoiding obstacle layers: 1 (buildings/resources), 2 (units)")

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
		UnitState.BUILDING:
			process_building(delta)
		UnitState.IDLE:
			move_and_slide()
			if animation_player and current_animation != "Idle":
				play_animation("Idle")

# ============ RESOURCE CARRYING SYSTEM ============

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
        if flow_field_active:
                _apply_flow_field_guidance()

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
					play_animation("Idle")
					return

		# Check if we reached a construction site for building
		if current_command and current_command.type == UnitCommand.CommandType.BUILD:
			if target_construction_site and is_instance_valid(target_construction_site):
				var distance = global_position.distance_to(target_construction_site.global_position)
				if distance <= BUILD_RANGE:
					print("Reached construction site, starting building")
					state = UnitState.BUILDING
					velocity = Vector3.ZERO
					play_animation("Idle")
					return

                state = UnitState.IDLE
                velocity.x = 0
                velocity.z = 0

                if has_facing_target:
                        rotation.y = target_facing_angle
                        has_facing_target = false

                flow_field_active = false
                flow_field_data.clear()

                play_animation("Idle")
                current_command = null
                return
	
	# Periodic path recalculation for dynamic obstacle avoidance
	path_recalc_timer += delta
	if path_recalc_timer >= path_recalc_interval:
		path_recalc_timer = 0.0
		# Recalculate path to handle moved obstacles or new buildings
		var current_target = navigation_agent.target_position
		navigation_agent.target_position = current_target  # Triggers recalc

	# Enhanced stuck detection with faster response
	check_timer += delta
	if check_timer >= stuck_check_interval:
		check_timer = 0.0

		var distance_moved = global_position.distance_to(last_check_position)
		var distance_to_target = global_position.distance_to(navigation_agent.target_position)

		if distance_moved < stuck_distance_threshold and distance_to_target > 2.0:
			stuck_timer += stuck_check_interval

			if stuck_timer >= max_stuck_time:
				print("⚠ Unit stuck! Attempting intelligent recovery...")
				_attempt_stuck_recovery()
		else:
			stuck_timer = 0.0
			stuck_recovery_attempts = 0

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

func _attempt_stuck_recovery():
	"""Intelligently attempt to recover from being stuck by trying multiple directions"""
	stuck_recovery_attempts += 1

	if stuck_recovery_attempts > MAX_RECOVERY_ATTEMPTS:
		print("  ✗ Max recovery attempts reached, giving up")
		state = UnitState.IDLE
		current_command = null
		stuck_timer = 0.0
		stuck_recovery_attempts = 0
		return

	var nav_map = get_world_3d().navigation_map
	var original_target = navigation_agent.target_position
	var direction_to_target = (original_target - global_position).normalized()

	# Try multiple probe directions around the obstacle
	var probe_directions = [
		direction_to_target.rotated(Vector3.UP, PI / 4),      # 45° right
		direction_to_target.rotated(Vector3.UP, -PI / 4),     # 45° left
		direction_to_target.rotated(Vector3.UP, PI / 2),      # 90° right
		direction_to_target.rotated(Vector3.UP, -PI / 2),     # 90° left
		-direction_to_target,                                  # Backwards
	]

	var probe_distance = 3.0  # Distance to probe for clear space
	var best_position: Vector3 = Vector3.ZERO
	var best_score: float = -INF

	# Use physics raycast to find clear direction
	var space_state = get_world_3d().direct_space_state

	for probe_dir in probe_directions:
		var probe_target = global_position + probe_dir * probe_distance

		# Raycast to check if path is clear
		var query = PhysicsRayQueryParameters3D.create(
			global_position + Vector3(0, 0.5, 0),  # Slightly above ground
			probe_target + Vector3(0, 0.5, 0)
		)
		query.collision_mask = 12  # Check buildings (layer 4) and resources (layer 3)
		query.exclude = [self]

		var raycast_result = space_state.intersect_ray(query)

		# If raycast is clear, check if position is on navmesh
		if not raycast_result:
			var navmesh_pos = NavigationServer3D.map_get_closest_point(nav_map, probe_target)

			# Score based on distance to navmesh point and progress toward target
			var navmesh_distance = probe_target.distance_to(navmesh_pos)
			var progress_to_target = navmesh_pos.distance_to(original_target)

			if navmesh_distance < 2.0:  # Position is reasonably close to navmesh
				var score = -progress_to_target - navmesh_distance * 2.0
				if score > best_score:
					best_score = score
					best_position = navmesh_pos

	# Apply best recovery position
	if best_position != Vector3.ZERO:
		print("  ✓ Found recovery path at attempt ", stuck_recovery_attempts)
		navigation_agent.target_position = best_position
		stuck_timer = 0.0

		# After reaching recovery position, repath to original target
		# We'll re-queue the original command after a brief pause
        else:
                print("  ⚠ No clear path found, trying random offset")
                # Fallback to deterministic random offset if intelligent recovery fails
                var rng := SimulationClock.create_rng(player_id, "worker_recovery_%s" % name)
                var random_offset = Vector3(
                        rng.randf_range(-4, 4),
                        0,
                        rng.randf_range(-4, 4)
                )
                var fallback_pos = NavigationServer3D.map_get_closest_point(
                        nav_map,
                        global_position + random_offset
                )
                navigation_agent.target_position = fallback_pos
                stuck_timer = 0.0

func _apply_flow_field_guidance() -> void:
        if flow_field_data.is_empty():
                flow_field_active = false
                return

        var direction := FlowField.sample_flow_field(flow_field_data, global_position)
        if direction == Vector3.ZERO:
                return

        var next_point := global_position + direction * FlowField.GRID_CELL_SIZE
        var nav_map := get_world_3d().navigation_map
        var snapped_point := NavigationServer3D.map_get_closest_point(nav_map, next_point)
        navigation_agent.target_position = snapped_point

        if global_position.distance_to(flow_field_goal) <= FlowField.GRID_CELL_SIZE * 1.5:
                flow_field_active = false
                flow_field_data.clear()

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
	
	if append:
		command_queue.append(command)
		print("📋 Queued command: ", command, " (queue size: ", command_queue.size(), ")")
        else:
                if state == UnitState.GATHERING and target_resource:
                        target_resource.stop_gathering(self)
                        target_resource = null

                command_queue.clear()
                current_command = null
                flow_field_active = false
                flow_field_data.clear()
                command_queue.append(command)
                print("📋 New command: ", command)

func _execute_command(command: UnitCommand):
	match command.type:
		UnitCommand.CommandType.MOVE:
			_execute_move_command(command)
		UnitCommand.CommandType.GATHER:
			_execute_gather_command(command)
		UnitCommand.CommandType.BUILD:
			_execute_build_command(command)
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

        flow_field_active = command.metadata.has("flow_field") and not command.metadata["flow_field"].is_empty()
        if flow_field_active:
                flow_field_data.clear()
                for entry in command.metadata["flow_field"]:
                        var cell: Vector3 = entry.get("cell", Vector3.ZERO)
                        var direction: Vector3 = entry.get("dir", Vector3.ZERO)
                        flow_field_data[cell] = direction
                flow_field_goal = command.metadata.get("flow_goal", target_position)
        else:
                flow_field_data.clear()

        state = UnitState.MOVING

func _execute_gather_command(command: UnitCommand):
	# If we have target_entity, use it directly (local command)
	if command.target_entity and is_instance_valid(command.target_entity):
		target_resource = command.target_entity
	else:
		# Network command - find resource at target position
		target_resource = _find_resource_at_position(command.target_position)
	
	if not target_resource or not is_instance_valid(target_resource):
		print("✗ Invalid resource target at ", command.target_position)
		current_command = null
		return
	
	if not target_resource.can_gather():
		print("✗ Resource depleted")
		current_command = null
		return
	
	print("✓ Moving to gather from ", target_resource.get_resource_type_string())
	
	# Ensure we have a dropoff building
	if not current_dropoff or not is_instance_valid(current_dropoff):
		find_nearest_dropoff()
	
	navigation_agent.target_position = target_resource.global_position
	state = UnitState.MOVING

func _find_resource_at_position(pos: Vector3) -> Node:
	"""Find resource node near the given position (for network commands)"""
	var resources = get_tree().get_nodes_in_group("resource_nodes")
	var closest: Node = null
	var closest_dist = 5.0  # Max search radius
	
	for resource in resources:
		if not is_instance_valid(resource):
			continue
		
		var dist = resource.global_position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = resource
	
	return closest

func _execute_build_command(command: UnitCommand):
	"""Execute build command - move to construction site and build"""
	var construction_sites = get_tree().get_nodes_in_group("construction_sites")
	var target_site: Node = null
	var closest_dist = 10.0  # Max search radius

	# Find construction site near target position
	for site in construction_sites:
		if not is_instance_valid(site):
			continue

		# Check if site is for the right building type and player
		if site.building_type != command.building_type:
			continue

		if site.player_id != player_id:
			continue

		var dist = site.global_position.distance_to(command.target_position)
		if dist < closest_dist:
			closest_dist = dist
			target_site = site

	if not target_site:
		print("✗ No construction site found for ", command.building_type, " at ", command.target_position)
		current_command = null
		return

	target_construction_site = target_site
	print("✓ Moving to build ", command.building_type)

	# Calculate a position on the perimeter of the construction site
	var build_position = target_site.get_build_position_for_worker(global_position)

	# Move to the perimeter position instead of the center
	navigation_agent.target_position = build_position
	state = UnitState.MOVING

func process_building(delta):
	"""Handle building/construction"""
	if not target_construction_site or not is_instance_valid(target_construction_site):
		print("⚠ Construction site lost!")
		state = UnitState.IDLE
		current_command = null
		target_construction_site = null
		return

	# Check if in build range (from the center of the construction site)
	var distance = global_position.distance_to(target_construction_site.global_position)
	if distance > BUILD_RANGE:
		# Move to a position on the perimeter instead of the center
		var build_position = target_construction_site.get_build_position_for_worker(global_position)
		navigation_agent.target_position = build_position
		state = UnitState.MOVING
		return

	# Face the construction site
	var direction = (target_construction_site.global_position - global_position).normalized()
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)

	# Add self to construction site builders (server only)
	if multiplayer.is_server():
		if target_construction_site.has_method("add_builder"):
			target_construction_site.add_builder(self)

		# Check if construction is complete
		if target_construction_site.get_progress_percent() >= 1.0:
			print("Construction complete!")
			construction_complete()

	# Play idle animation while building
	if animation_player and current_animation != "Idle":
		play_animation("Idle")

func construction_complete():
	"""Called when construction is complete"""
	if target_construction_site and is_instance_valid(target_construction_site):
		if target_construction_site.has_method("remove_builder"):
			target_construction_site.remove_builder(self)

	target_construction_site = null
	state = UnitState.IDLE
	current_command = null
	print("Worker finished construction")

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
	
func get_state_name() -> String:
	match state:
		UnitState.IDLE: return "Idle"
		UnitState.MOVING: return "Moving"
		UnitState.GATHERING: return "Gathering"
		UnitState.RETURNING: return "Returning"
		UnitState.DEPOSITING: return "Depositing"
		UnitState.BUILDING: return "Building"
	return "Unknown"

func get_carried_amount() -> int:
	var total = 0
	for amount in carrying_resources.values():
		total += amount
	return total
