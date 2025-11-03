extends Node

signal selection_changed(selected_units: Array)
signal move_command_issued(target_position: Vector3, units: Array)
signal building_selected(building: Node)
signal building_deselected()

# Selection state
var selected_units: Array = []  # Units only (movable)
var selected_building: Node = null  # Single building selection

# Rally point mode
var rally_mode_active: bool = false
var rally_mode_building: Node = null

# Box selection
var is_box_selecting: bool = false
var box_select_start: Vector2 = Vector2.ZERO
var box_select_end: Vector2 = Vector2.ZERO

# Formation system
var current_formation: FormationManager.FormationType = FormationManager.FormationType.LINE
var use_flow_field: bool = false  # ADD THIS - toggle with F key
var is_rotating_formation: bool = false
var formation_rotation: float = 0.0
var formation_center: Vector3 = Vector3.ZERO
var rotation_start_pos: Vector2 = Vector2.ZERO

# Camera reference
var camera: Camera3D = null

# Input settings
const SELECTION_BOX_MIN_SIZE = 5.0
const ROTATION_DRAG_THRESHOLD = 10.0  # Pixels to start rotation

func _ready():
	pass

func set_camera(cam: Camera3D):
	camera = cam

# CRITICAL FIX: Changed from _input to _unhandled_input
# This ensures UI clicks are handled first and won't trigger world selection
func _unhandled_input(event):
	if not camera:
		return
	
	# Toggle flow field mode
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		use_flow_field = not use_flow_field
		print("Flow field mode: ", "ENABLED" if use_flow_field else "DISABLED")
		get_viewport().set_input_as_handled()
	
	# Left mouse button - selection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_mouse_down(event.position)
		else:
			_on_left_mouse_up(event.position)
		get_viewport().set_input_as_handled()
	
	# Right mouse button - movement command with rotation (only for units) OR rally point setting
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			# Check if in rally mode first
			if rally_mode_active:
				_set_rally_point(event.position)
				get_viewport().set_input_as_handled()
			elif selected_units.size() > 0:
				_on_right_mouse_down(event.position)
				get_viewport().set_input_as_handled()
		else:
			_on_right_mouse_up()
			get_viewport().set_input_as_handled()
	
	# Mouse motion for box select and formation rotation
	if event is InputEventMouseMotion:
		if is_box_selecting:
			box_select_end = event.position
		elif is_rotating_formation:
			_update_formation_rotation(event.position)

func _on_left_mouse_down(mouse_pos: Vector2):
	box_select_start = mouse_pos
	box_select_end = mouse_pos
	is_box_selecting = true
	
	var additive = Input.is_key_pressed(KEY_SHIFT)
	
	if not additive:
		clear_selection()

func _on_left_mouse_up(mouse_pos: Vector2):
	var box_size = (mouse_pos - box_select_start).length()
	
	if box_size < SELECTION_BOX_MIN_SIZE:
		_handle_single_select(mouse_pos)
	else:
		_handle_box_select()
	
	is_box_selecting = false

func _on_right_mouse_down(mouse_pos: Vector2):
	# Don't issue commands if a building is selected
	if selected_building:
		print("Cannot issue movement commands to buildings")
		return
	
	# Only issue commands if units are selected
	if selected_units.size() == 0:
		return
	
	# Raycast to find target position or resource
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var clicked_object = result.collider

		# Check if clicked on a construction site
		if clicked_object.is_in_group("construction_sites"):
			_issue_build_command(clicked_object)
			return

		# Check if clicked on a resource node
		if clicked_object.is_in_group("resource_nodes"):
			_issue_gather_command(clicked_object)
			return

		# Otherwise, it's a move command (only for units)
		formation_center = result.position
		rotation_start_pos = mouse_pos
		is_rotating_formation = true
		formation_rotation = 0.0

func _issue_gather_command(resource_node: Node):
	"""Issue gather command to selected units"""
	var queue_mode = Input.is_key_pressed(KEY_SHIFT)
	var resource_type = resource_node.get_resource_type_string()

	print("Gather command: ", selected_units.size(), " units → ", resource_type, " node")

	for unit in selected_units:
		if is_instance_valid(unit) and unit.is_multiplayer_authority():
			# Check if unit can gather
			if not unit.has_method("queue_command"):
				continue

			var command = UnitCommand.new(UnitCommand.CommandType.GATHER)
			command.target_entity = resource_node  # FIX: Use target_entity not target_resource
			command.target_position = resource_node.global_position  # FIX: Add position for network sync

			# Queue or replace based on shift key
			unit.queue_command(command, queue_mode)

func _issue_build_command(construction_site: Node):
	"""Issue build command to selected units for a construction site"""
	var queue_mode = Input.is_key_pressed(KEY_SHIFT)

	print("Build command: ", selected_units.size(), " units → construction site")

	# Get building placement manager from game
	var game = get_tree().root.get_node_or_null("Game")
	if not game:
		print("Game node not found")
		return

	var placement_manager = null
	for child in game.get_children():
		if child is BuildingPlacementManager:
			placement_manager = child
			break

	if not placement_manager:
		print("Building placement manager not found")
		return

	# Filter only workers
	var workers = []
	for unit in selected_units:
		if is_instance_valid(unit) and unit.is_in_group("worker"):
			workers.append(unit)

	if workers.is_empty():
		print("No workers selected to build")
		return

	# Assign workers to construction site
	placement_manager.assign_workers_to_construction_site(construction_site, workers, queue_mode)

func _on_right_mouse_up():
	if is_rotating_formation and selected_units.size() > 0:
		# Issue move command with formation
		_issue_formation_move_command()
	
	is_rotating_formation = false
	formation_rotation = 0.0

func _issue_formation_move_command():
	var queue_mode = Input.is_key_pressed(KEY_SHIFT)
	
	# Calculate facing angle
	var facing_angle = formation_rotation
	
	# If no rotation was applied, calculate direction from units to target
	if abs(formation_rotation) < 0.01:
		var avg_position = Vector3.ZERO
		var valid_count = 0
		for unit in selected_units:
			if is_instance_valid(unit):
				avg_position += unit.global_position
				valid_count += 1
		
		if valid_count > 0:
			avg_position /= valid_count
			var direction = (formation_center - avg_position).normalized()
			facing_angle = atan2(direction.x, direction.z)
	
	# Get formation positions with facing angle
	var formation_positions = FormationManager.calculate_formation_positions(
		formation_center,
		selected_units.size(),
		current_formation,
		facing_angle
	)

	# Validate positions against NavMesh AND physical obstacles
	var world = get_tree().root.get_world_3d()
	var nav_map = world.navigation_map
	formation_positions = FormationManager.validate_and_adjust_positions(
		formation_positions,
		world,
		nav_map
	)
	
	# Debug
	var queue_text = "QUEUED" if queue_mode else "NEW"
	print("Move command (", queue_text, "): ", selected_units.size(), " units")
	
	# Create move commands for each unit
	for i in range(selected_units.size()):
		var unit = selected_units[i]
		if is_instance_valid(unit) and unit.is_multiplayer_authority():
			var command = UnitCommand.new(UnitCommand.CommandType.MOVE)
			command.target_position = formation_positions[i]
			command.facing_angle = facing_angle
			
			# Queue or replace based on shift key
			unit.queue_command(command, queue_mode)
	
	move_command_issued.emit(formation_center, selected_units)

func _update_formation_rotation(mouse_pos: Vector2):
	var drag_distance = mouse_pos.distance_to(rotation_start_pos)
	
	if drag_distance < ROTATION_DRAG_THRESHOLD:
		formation_rotation = 0.0
		return
	
	# Calculate angle from formation center
	var delta = mouse_pos - rotation_start_pos
	formation_rotation = atan2(delta.x, -delta.y)  # Negative Y because screen coords

func _handle_single_select(mouse_pos: Vector2):
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var clicked_object = result.collider
		var entity = _find_unit_or_building_from_collider(clicked_object)
		
		if entity:
			# Check if it's a building
			if entity.is_in_group("buildings"):
				# Clear unit selection, select building
				clear_selection()
				selected_building = entity
				entity.select()
				building_selected.emit(entity)
				print("Building selected: ", entity.building_name)
			# Check if it's a unit
			elif entity.is_in_group("units"):
				# Clear building selection, add to unit selection
				if selected_building:
					if is_instance_valid(selected_building):
						selected_building.deselect()
					selected_building = null
					building_deselected.emit()
				
				if not selected_units.has(entity):
					selected_units.append(entity)
					entity.select()
					selection_changed.emit(selected_units)
		else:
			clear_selection()

func _handle_box_select():
	var all_units = get_tree().get_nodes_in_group("units")
	var box_rect = _get_box_rect()
	
	for unit in all_units:
		var unit_screen_pos = camera.unproject_position(unit.global_position)
		
		if box_rect.has_point(unit_screen_pos):
			if not selected_units.has(unit):
				selected_units.append(unit)
				unit.select()
	
	if selected_units.size() > 0:
		selection_changed.emit(selected_units)

func _get_box_rect() -> Rect2:
	var box_min = Vector2(
		min(box_select_start.x, box_select_end.x),
		min(box_select_start.y, box_select_end.y)
	)
	var box_max = Vector2(
		max(box_select_start.x, box_select_end.x),
		max(box_select_start.y, box_select_end.y)
	)
	return Rect2(box_min, box_max - box_min)

func _find_unit_or_building_from_collider(collider: Node) -> Node:
	var current = collider
	while current:
		# Check for units
		if current.has_method("select") and current.has_method("deselect") and current.is_in_group("units"):
			return current
		# Check for buildings
		if current.has_method("select") and current.has_method("deselect") and current.is_in_group("buildings"):
			return current
		current = current.get_parent()
	return null

func clear_selection():
	# Clear units
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.deselect()
	selected_units.clear()
	selection_changed.emit(selected_units)
	
	# Clear building
	if selected_building:
		if is_instance_valid(selected_building):
			selected_building.deselect()
		selected_building = null
		building_deselected.emit()

func get_selected_units() -> Array:
	return selected_units

func get_selected_building() -> Node:
	return selected_building

# ============ RALLY POINT SYSTEM ============

func activate_rally_mode(building: Node):
	"""Activate rally point setting mode for a building"""
	rally_mode_active = true
	rally_mode_building = building
	print("Rally mode activated for: ", building.building_name)

func deactivate_rally_mode():
	"""Deactivate rally point setting mode"""
	rally_mode_active = false
	rally_mode_building = null
	print("Rally mode deactivated")

func _set_rally_point(mouse_pos: Vector2):
	"""Set rally point for the building (called on right-click in rally mode)"""
	if not rally_mode_building or not is_instance_valid(rally_mode_building):
		print("❌ Rally mode building invalid!")
		deactivate_rally_mode()
		return

	# Raycast to find target position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0

	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result:
		var rally_position = result.position
		var clicked_object = result.collider

		# Check if clicked on a resource node
		var resource_path = NodePath()
		if clicked_object.is_in_group("resource_nodes"):
			resource_path = clicked_object.get_path()
			print("Rally point set on resource node: ", clicked_object.get_resource_type_string())

		# Send rally point to server
		if multiplayer.is_server():
			# Server sets directly
			_apply_rally_point(rally_mode_building.get_path(), rally_position, resource_path)
		else:
			# Client sends RPC to server
			request_set_rally_point.rpc_id(1, rally_mode_building.get_path(), rally_position, resource_path)

		print("Rally point set to: ", rally_position)

	# Deactivate rally mode after setting
	deactivate_rally_mode()

	# Notify production UI to update button
	var production_ui = get_tree().root.get_node_or_null("Game/GameUI/ProductionUI")
	if production_ui and production_ui.has_method("deactivate_rally_mode"):
		production_ui.deactivate_rally_mode()

@rpc("any_peer", "call_remote", "reliable")
func request_set_rally_point(building_path: NodePath, rally_position: Vector3, resource_path: NodePath):
	"""Server receives rally point request from client"""
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	var building = get_node_or_null(building_path)

	if not building or not is_instance_valid(building):
		print("❌ Building not found at path: ", building_path)
		return

	# Verify ownership
	if building.player_id != sender_id:
		print("❌ Player ", sender_id, " tried to set rally point for player ", building.player_id, "'s building!")
		return

	_apply_rally_point(building_path, rally_position, resource_path)

func _apply_rally_point(building_path: NodePath, rally_position: Vector3, resource_path: NodePath):
	"""Apply rally point to building (server only)"""
	var building = get_node_or_null(building_path)
	if not building or not is_instance_valid(building):
		return

	var resource_node = null
	if resource_path != NodePath():
		resource_node = get_node_or_null(resource_path)

	# Set rally point on the building
	if resource_node and is_instance_valid(resource_node):
		if building.has_method("set_rally_point_with_resource"):
			building.set_rally_point_with_resource(rally_position, resource_node)
	else:
		if building.has_method("set_rally_point"):
			building.set_rally_point(rally_position)
