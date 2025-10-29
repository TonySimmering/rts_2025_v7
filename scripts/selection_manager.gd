extends Node

signal selection_changed(selected_units: Array)
signal move_command_issued(target_position: Vector3, units: Array)
signal building_selected(building: Node)
signal building_deselected()

# Selection state
var selected_units: Array = []  # Units only (movable)
var selected_building: Node = null  # Single building selection

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

func _input(event):
	if not camera:
		return
	
	# Toggle flow field mode
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		use_flow_field = not use_flow_field
		print("Flow field mode: ", "ENABLED" if use_flow_field else "DISABLED")
	
	# Left mouse button - selection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_mouse_down(event.position)
		else:
			_on_left_mouse_up(event.position)
	
	# Right mouse button - movement command with rotation (only for units)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and selected_units.size() > 0:
			_on_right_mouse_down(event.position)
		else:
			_on_right_mouse_up()
	
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
	
	print("Gather command: ", selected_units.size(), " units → ", resource_type, " resource", " [QUEUED]" if queue_mode else "")
	
	for unit in selected_units:
		if is_instance_valid(unit) and unit.is_multiplayer_authority():
			var command = UnitCommand.new(UnitCommand.CommandType.GATHER)
			command.target_position = resource_node.global_position
			command.target_entity = resource_node
			
			unit.queue_command(command, queue_mode)

func _on_right_mouse_up():
	if not is_rotating_formation:
		return
	
	is_rotating_formation = false
	
	# Check if shift is held (queue mode)
	var queue_mode = Input.is_key_pressed(KEY_SHIFT)
	
	# Calculate facing angle
	var facing_angle = formation_rotation
	
	# If no rotation was applied, calculate direction from units to target
	var drag_distance = get_viewport().get_mouse_position().distance_to(rotation_start_pos)
	if drag_distance < ROTATION_DRAG_THRESHOLD:
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
	
	# Issue move command with formation
	var formation_positions = FormationManager.calculate_formation_positions(
		formation_center,
		selected_units.size(),
		current_formation,
		facing_angle
	)
	
	# Validate each position against NavMesh
	var nav_map = get_tree().root.get_world_3d().navigation_map
	for i in range(formation_positions.size()):
		var original_pos = formation_positions[i]
		var valid_pos = NavigationServer3D.map_get_closest_point(nav_map, original_pos)
		formation_positions[i] = valid_pos
	
	var queue_text = " [QUEUED]" if queue_mode else ""
	print("Move command to: ", formation_center, " with angle: ", rad_to_deg(facing_angle), " degrees", queue_text)
	
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
