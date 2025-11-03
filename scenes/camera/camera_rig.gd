extends Node3D

# Reference to child nodes
@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

# Movement settings
@export var pan_speed: float = 20
@export var edge_scroll_margin: float = 20.0  # pixels from edge
@export var edge_scroll_speed: float = 15.0

# Rotation settings
@export var rotation_speed: float = 90.0  # degrees per second

# Zoom settings
@export var zoom_speed: float = 1.5
@export var min_zoom_distance: float = 1
@export var max_zoom_distance: float = 15
@export var min_pitch: float = -10.0  # looking more horizontal
@export var max_pitch: float = -70.0  # looking more vertical

# Map boundaries (will set these later)
@export var map_min: Vector3 = Vector3(-50, 0, -50)
@export var map_max: Vector3 = Vector3(128, 0, 128)

# Smoothing
@export var movement_smoothing: float = 10.0
@export var rotation_smoothing: float = 5.0
@export var zoom_smoothing: float = 8.0

@export var terrain_offset: float = 1
@export var height_smoothing: float = 5.0

# Smart DOF settings
@export var dof_enabled: bool = true
@export var dof_transition_angle: float = -30.0  # Angle (degrees) where DOF starts transitioning
@export var dof_max_angle: float = -10.0  # Angle (degrees) where DOF is maximum
@export var dof_max_blur_far: float = 0.15  # Maximum far blur when horizontal
@export var dof_max_blur_near: float = 0.05  # Maximum near blur when horizontal
@export var dof_focus_offset: float = 0.0  # Offset from calculated focus distance
@export var dof_smoothing: float = 8.0  # Smoothing for DOF parameter transitions

var terrain: Node3D = null
var camera_attributes: CameraAttributesPractical = null

# Internal DOF state
var current_focus_distance: float = 10.0
var target_focus_distance: float = 10.0
var current_blur_amount: float = 0.0
var target_blur_amount: float = 0.0

# Internal state
var current_zoom: float = 0.5  # 0 = max zoom out, 1 = max zoom in
var target_zoom: float = 0.5
var velocity: Vector3 = Vector3.ZERO
var target_rotation_y: float = 0.0

func _ready():
	# Set initial camera position
	apply_zoom()
	target_rotation_y = rotation.y

func _process(delta):
	handle_input(delta)
	update_camera_transform(delta)
	smooth_zoom(delta)
	update_smart_dof(delta)

func handle_input(delta):
	# Skip input if UI is focused (we'll add this check later)
	# For now we'll always accept input
	
	var input_dir = Vector3.ZERO
	
	# Keyboard panning (WASD or Arrow keys)
	if Input.is_action_pressed("ui_up"):
		input_dir -= transform.basis.z
	if Input.is_action_pressed("ui_down"):
		input_dir += transform.basis.z
	if Input.is_action_pressed("ui_left"):
		input_dir -= transform.basis.x
	if Input.is_action_pressed("ui_right"):
		input_dir += transform.basis.x
	
	# Edge scrolling
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	
	if mouse_pos.x < edge_scroll_margin:
		input_dir -= transform.basis.x * edge_scroll_speed * delta
	elif mouse_pos.x > viewport_size.x - edge_scroll_margin:
		input_dir += transform.basis.x * edge_scroll_speed * delta
	
	if mouse_pos.y < edge_scroll_margin:
		input_dir -= transform.basis.z * edge_scroll_speed * delta
	elif mouse_pos.y > viewport_size.y - edge_scroll_margin:
		input_dir += transform.basis.z * edge_scroll_speed * delta
	
	# Normalize and apply pan speed
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
		velocity = input_dir * pan_speed
	else:
		velocity = velocity.lerp(Vector3.ZERO, movement_smoothing * delta)
	
	# Rotation (Q and E keys)
	if Input.is_action_pressed("camera_rotate_left"):
		target_rotation_y += rotation_speed * delta * PI / 180.0
	if Input.is_action_pressed("camera_rotate_right"):
		target_rotation_y -= rotation_speed * delta * PI / 180.0

func _unhandled_input(event):
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clamp(target_zoom + zoom_speed * 0.1, 0.0, 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clamp(target_zoom - zoom_speed * 0.1, 0.0, 1.0)

func smooth_zoom(delta):
	# Smoothly interpolate to target zoom
	current_zoom = lerp(current_zoom, target_zoom, zoom_smoothing * delta)
	apply_zoom()

func update_camera_transform(delta):
	position += velocity * delta
	position.x = clamp(position.x, map_min.x, map_max.x)
	position.z = clamp(position.z, map_min.z, map_max.z)
	
	if terrain:
		var terrain_height = get_terrain_height_at_position(position)
		var target_y = terrain_height + terrain_offset
		position.y = lerp(position.y, target_y, height_smoothing * delta)
	
	rotation.y = lerp_angle(rotation.y, target_rotation_y, rotation_smoothing * delta)

func apply_zoom():
	# Use ease-in-out curve for smooth "swoop" effect
	var zoom_curve = ease(current_zoom, -2.0)  # Negative value creates ease-in-out
	
	# Interpolate distance and pitch based on curved zoom level
	var distance = lerp(max_zoom_distance, min_zoom_distance, zoom_curve)
	var pitch = lerp(max_pitch, min_pitch, zoom_curve)
	
	# Apply to camera
	camera.position.z = distance
	pivot.rotation.x = deg_to_rad(pitch)

func focus_on_position(target_pos: Vector3):
	"""Move camera to look at a specific position"""
	position = target_pos
	velocity = Vector3.ZERO
	
func set_terrain(terrain_node: Node3D):
	terrain = terrain_node
	print("Camera rig terrain reference set")

func set_environment(env: Environment):
	# DOF now uses CameraAttributes in Godot 4.5, not Environment
	# Create camera attributes if DOF is enabled
	if dof_enabled:
		camera_attributes = CameraAttributesPractical.new()
		camera_attributes.dof_blur_far_enabled = true
		camera_attributes.dof_blur_near_enabled = true
		camera.attributes = camera_attributes
		print("Camera rig Smart DOF enabled using CameraAttributes")

func get_terrain_height_at_position(world_pos: Vector3) -> float:
	if not terrain or not terrain.has_method("get_height_at_position"):
		return 0.0
	return terrain.get_height_at_position(world_pos)

func update_smart_dof(delta):
	"""Smart DOF system: Full DOF when zoomed out, shallow DOF when close and horizontal"""
	if not dof_enabled or not camera_attributes:
		return

	# Get current pitch angle in degrees
	var pitch_deg = rad_to_deg(pivot.rotation.x)

	# Calculate blur amount based on pitch angle
	# When pitch is steep (like -70), blur_factor = 0 (no blur)
	# When pitch is horizontal (like -10), blur_factor = 1 (max blur)
	var blur_factor = 0.0
	if pitch_deg > dof_transition_angle:
		# We're past the transition angle, moving towards horizontal
		var angle_range = dof_max_angle - dof_transition_angle
		var current_offset = pitch_deg - dof_transition_angle
		blur_factor = clamp(current_offset / angle_range, 0.0, 1.0)
		# Use ease for smoother transition
		blur_factor = ease(blur_factor, -2.0)  # Ease in-out

	target_blur_amount = blur_factor

	# Calculate focus distance based on camera position and angle
	# Ray cast from camera towards terrain to find focus point
	var camera_global_pos = camera.global_position
	var camera_forward = -camera.global_transform.basis.z

	# Estimate where we're looking at the terrain
	# Use simple geometric calculation for focus distance
	var estimated_focus_distance = camera.position.z * 0.8  # 80% of camera distance as baseline

	# If we have terrain, calculate actual intersection point
	if terrain:
		var camera_height = camera_global_pos.y
		var terrain_height = get_terrain_height_at_position(global_position)
		var height_diff = camera_height - terrain_height

		# Calculate distance to terrain intersection using camera angle
		if camera_forward.y < -0.01:  # Looking downward
			var distance_to_terrain = height_diff / abs(camera_forward.y)
			estimated_focus_distance = clamp(distance_to_terrain, 1.0, 50.0)

	target_focus_distance = estimated_focus_distance + dof_focus_offset

	# Smoothly interpolate DOF parameters
	current_focus_distance = lerp(current_focus_distance, target_focus_distance, dof_smoothing * delta)
	current_blur_amount = lerp(current_blur_amount, target_blur_amount, dof_smoothing * delta)

	# Apply to camera attributes (Godot 4.5+)
	# Note: CameraAttributesPractical uses a single dof_blur_amount for both near and far
	camera_attributes.dof_blur_far_enabled = current_blur_amount > 0.01
	camera_attributes.dof_blur_near_enabled = current_blur_amount > 0.01

	if current_blur_amount > 0.01:
		# Set distances and transitions
		camera_attributes.dof_blur_far_distance = current_focus_distance
		camera_attributes.dof_blur_far_transition = 5.0  # Smooth transition

		camera_attributes.dof_blur_near_distance = current_focus_distance * 0.5
		camera_attributes.dof_blur_near_transition = 2.0

		# CameraAttributesPractical uses single blur amount property
		# Use the far blur amount as it's typically more visible
		camera_attributes.dof_blur_amount = current_blur_amount * dof_max_blur_far
