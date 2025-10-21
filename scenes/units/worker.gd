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
var is_selected: bool = false
var current_animation: String = "Idle"
var animation_player: AnimationPlayer = null

# State
enum UnitState { IDLE, MOVING, CHOPPING }
var state: UnitState = UnitState.IDLE

func _ready():
	add_to_group("units")
	
	print("\n=== WORKER UNIT READY ===")
	print("Worker position: ", global_position)
	
	animation_player = find_child("AnimationPlayer", true, false)
	
	if not animation_player:
		var glb_node = model.get_child(0) if model.get_child_count() > 0 else null
		if glb_node:
			print("Found GLB node: ", glb_node.name)
			animation_player = glb_node.find_child("AnimationPlayer", true, false)
	
	if animation_player:
		print("✓ AnimationPlayer found at: ", animation_player.get_path())
		print("  Available animations: ", animation_player.get_animation_list())
		play_animation("Idle")
	else:
		push_error("✗ AnimationPlayer NOT found!")
	
	call_deferred("setup_agent")
	selection_indicator.visible = false
	print("=========================\n")

func setup_agent():
	# Wait for NavigationServer to be ready
	await get_tree().physics_frame
	await get_tree().physics_frame  # Extra wait
	await get_tree().physics_frame
	
	print("NavigationAgent setup:")
	print("  Map RID valid: ", navigation_agent.get_navigation_map().is_valid())
	print("  Agent avoidance enabled: ", navigation_agent.avoidance_enabled)
	
	navigation_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta):
	match state:
		UnitState.MOVING:
			process_movement(delta)
		UnitState.IDLE:
			if animation_player and current_animation != "Idle":
				play_animation("Idle")

func process_movement(delta):
	# Debug output
	if Engine.get_physics_frames() % 60 == 0:  # Print every 2 seconds
		print("Movement debug:")
		print("  Position: ", global_position)
		print("  Target: ", navigation_agent.target_position)
		print("  Distance remaining: ", navigation_agent.distance_to_target())
		print("  Is nav finished: ", navigation_agent.is_navigation_finished())
		print("  Is target reachable: ", navigation_agent.is_target_reachable())
		print("  Path exists: ", not navigation_agent.is_navigation_finished())
	
	if navigation_agent.is_navigation_finished():
		print("Navigation finished! Stopping.")
		state = UnitState.IDLE
		velocity = Vector3.ZERO
		play_animation("Idle")
		return
	
	var next_position = navigation_agent.get_next_path_position()
	var direction = (next_position - global_position).normalized()
	
	print("Next pos: ", next_position, " Direction: ", direction)  # ADD THIS
	
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 10.0)
	
	var desired_velocity = direction * move_speed
	navigation_agent.set_velocity(desired_velocity)
	
	if animation_player and current_animation != "Walk":
		play_animation("Walk")

func _on_velocity_computed(safe_velocity: Vector3):
	print("Velocity computed: ", safe_velocity)  # ADD THIS
	velocity = safe_velocity
	move_and_slide()
	print("After move_and_slide, position: ", global_position)  # ADD THIS

func move_to_position(target_position: Vector3):
	print("\n=== MOVE COMMAND ===")
	print("Worker at: ", global_position)
	print("Target: ", target_position)
	
	# Get the navigation map
	var nav_map = get_world_3d().navigation_map
	
	# DEBUG: Try to get the closest point on navmesh
	var closest_point = NavigationServer3D.map_get_closest_point(nav_map, global_position)
	print("Closest NavMesh point to worker: ", closest_point)
	print("Distance from worker to NavMesh: ", global_position.distance_to(closest_point))
	
	var closest_target = NavigationServer3D.map_get_closest_point(nav_map, target_position)
	print("Closest NavMesh point to target: ", closest_target)
	print("Distance from target to NavMesh: ", target_position.distance_to(closest_target))
	
	# Query path
	var path = NavigationServer3D.map_get_path(
		nav_map,
		global_position,
		target_position,
		true
	)
	
	print("Path points: ", path.size())
	
	if path.size() > 0:
		print("✓ Path found with ", path.size(), " waypoints")
		navigation_agent.target_position = target_position
		state = UnitState.MOVING
	else:
		print("✗ No path found!")
	
	print("===================\n")
	
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
	else:
		push_warning("Animation '", anim_name, "' not found. Available: ", animation_player.get_animation_list())

func get_owner_id() -> int:
	return player_id
