extends Node

signal selection_changed(selected_units: Array)
signal move_command_issued(target_position: Vector3, units: Array)

# Selection state
var selected_units: Array = []

# Box selection
var is_box_selecting: bool = false
var box_select_start: Vector2 = Vector2.ZERO
var box_select_end: Vector2 = Vector2.ZERO

# Camera reference
var camera: Camera3D = null

# Input settings
const SELECTION_BOX_MIN_SIZE = 5.0

func _ready():
	pass

func set_camera(cam: Camera3D):
	camera = cam

func _input(event):
	if not camera:
		return
	
	# Left mouse button - selection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_mouse_down(event.position)
		else:
			_on_left_mouse_up(event.position)
	
	# Right mouse button - movement command  # ADD THIS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and selected_units.size() > 0:
			_on_right_mouse_down(event.position)
	
	# Mouse motion for box select
	if event is InputEventMouseMotion:
		if is_box_selecting:
			box_select_end = event.position

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

# ADD THIS NEW FUNCTION
func _on_right_mouse_down(mouse_pos: Vector2):
	# Raycast to find target position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var target_position = result.position
		print("Move command to: ", target_position, " for ", selected_units.size(), " units")
		
		# Calculate formation positions if multiple units
		var formation_positions = _calculate_formation_positions(target_position, selected_units.size())
		
		# Issue move commands
		for i in range(selected_units.size()):
			var unit = selected_units[i]
			if is_instance_valid(unit):
				unit.move_to_position(formation_positions[i])
		
		move_command_issued.emit(target_position, selected_units)

# ADD THIS NEW FUNCTION
func _calculate_formation_positions(center: Vector3, unit_count: int) -> Array:
	var positions = []
	
	if unit_count == 1:
		positions.append(center)
		return positions
	
	# Simple grid formation
	var spacing = 2.0  # Distance between units
	var columns = ceil(sqrt(unit_count))
	var rows = ceil(unit_count / columns)
	
	var start_x = center.x - (columns - 1) * spacing * 0.5
	var start_z = center.z - (rows - 1) * spacing * 0.5
	
	for i in range(unit_count):
		var col = i % int(columns)
		var row = i / int(columns)
		
		var pos = Vector3(
			start_x + col * spacing,
			center.y,
			start_z + row * spacing
		)
		positions.append(pos)
	
	return positions

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
		var unit = _find_unit_from_collider(clicked_object)
		
		if unit:
			if not selected_units.has(unit):
				selected_units.append(unit)
				unit.select()
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

func _find_unit_from_collider(collider: Node) -> Node:
	var current = collider
	while current:
		if current.has_method("select") and current.has_method("deselect"):
			return current
		current = current.get_parent()
	return null

func clear_selection():
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.deselect()
	selected_units.clear()
	selection_changed.emit(selected_units)

func get_selected_units() -> Array:
	return selected_units
