extends Node

signal selection_changed(selected_units: Array)
signal move_command_issued(target_position: Vector3, units: Array)

# Selection state
var selected_units: Array = []

# Box selection
var is_box_selecting: bool = false
var box_select_start: Vector2 = Vector2.ZERO
var box_select_end: Vector2 = Vector2.ZERO

# Formation system
var current_formation: FormationManager.FormationType = FormationManager.FormationType.LINE
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
	
	# Left mouse button - selection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_mouse_down(event.position)
		else:
			_on_left_mouse_up(event.position)
	
	# Right mouse button - movement command with rotation
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
	# Raycast to find target position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result:
		formation_center = result.position
		rotation_start_pos = mouse_pos
		is_rotating_formation = true
		formation_rotation = 0.0

func _on_right_mouse_up():
	if not is_rotating_formation:
		return
	
	is_rotating_formation = false
	
	# Issue move command with formation
	var formation_positions = FormationManager.calculate_formation_positions(
		formation_center,
		selected_units.size(),
		current_formation,
		formation_rotation
	)
	
	print("Move command to: ", formation_center, " with angle: ", rad_to_deg(formation_rotation), " degrees")
	
	# Issue move commands
	for i in range(selected_units.size()):
		var unit = selected_units[i]
		if is_instance_valid(unit) and unit.is_multiplayer_authority():
			unit.move_to_position(formation_positions[i])
	
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
