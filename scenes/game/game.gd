extends Node3D

@onready var info_label = $CanvasLayer/InfoLabel

const CAMERA_RIG_SCENE = preload("res://scenes/camera/camera_rig.tscn")

var local_camera: Node3D = null
var selection_manager: Node = null
var selection_box: Control = null
var spawn_manager: Node = null  # ADD THIS

func _ready():
	print("=== GAME SCENE LOADED ===")
	print("Is Server:", multiplayer.is_server())
	print("My ID:", multiplayer.get_unique_id())
	print("Connected Players:", NetworkManager.players)
	print("Game Seed:", NetworkManager.game_seed)
	
	spawn_local_camera()
	setup_selection_system()
	await generate_terrain_with_seed()  # ADD AWAIT
	setup_spawn_system()  # ADD THIS
	spawn_starting_units()  # ADD THIS
	
	NetworkManager.player_connected.connect(_on_player_joined)
	NetworkManager.player_disconnected.connect(_on_player_left)
	
	update_info()

func spawn_local_camera():
	local_camera = CAMERA_RIG_SCENE.instantiate()
	add_child(local_camera)
	print("Local camera spawned for player ", multiplayer.get_unique_id())

func setup_selection_system():
	selection_manager = Node.new()
	selection_manager.set_script(load("res://scripts/selection_manager.gd"))
	add_child(selection_manager)
	
	await get_tree().process_frame
	
	if local_camera:
		var camera = local_camera.get_node("CameraPivot/Camera3D")
		selection_manager.set_camera(camera)
	
	selection_box = Control.new()
	selection_box.set_script(load("res://scripts/selection_box.gd"))
	selection_box.selection_manager = selection_manager
	$CanvasLayer.add_child(selection_box)
	
	selection_manager.selection_changed.connect(_on_selection_changed)
	
	print("Selection system initialized")

func setup_spawn_system():  # ADD THIS FUNCTION
	spawn_manager = Node.new()
	spawn_manager.set_script(load("res://scripts/spawn_manager.gd"))
	spawn_manager.terrain = get_node_or_null("Terrain")
	add_child(spawn_manager)
	print("Spawn system initialized")

func spawn_starting_units():
	if not multiplayer.is_server():
		return
	
	await get_tree().create_timer(0.5).timeout

	# Get terrain size for spawn calculation
	var terrain = get_node_or_null("Terrain")
	var map_size = Vector2(128, 128)  # Default from terrain settings
	
	# Spawn units for each player
	for player_id in NetworkManager.players:
		var spawn_center = spawn_manager.get_spawn_location_for_player(player_id, map_size)
		spawn_manager.spawn_starting_units(player_id, spawn_center)
		
	if terrain:
		print("\n=== TERRAIN DEBUG ===")
		print("Terrain global position: ", terrain.global_position)
		var nav_region = terrain.get_node_or_null("NavigationRegion3D")
		if nav_region:
			print("NavigationRegion global position: ", nav_region.global_position)
			print("NavigationRegion transform: ", nav_region.transform)
		print("=====================\n")
		
func _on_selection_changed(selected_units: Array):
	print("Selection changed: ", selected_units.size(), " units selected")
	update_info()

func generate_terrain_with_seed():
	var terrain = get_node_or_null("Terrain")
	if terrain and terrain.has_method("generate_terrain"):
		await terrain.generate_terrain(NetworkManager.game_seed)  # ADD AWAIT
		print("Terrain generation complete, ready for spawning")
	else:
		push_error("Terrain node not found!")

func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		print("Returning to menu...")
		NetworkManager.disconnect_from_game()
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

func _on_player_joined(peer_id: int, player_info: Dictionary):
	print("Game scene notified: Player joined - ", peer_id)
	update_info()

func _on_player_left(peer_id: int):
	print("Game scene notified: Player left - ", peer_id)
	update_info()

func update_info():
	var text = "GAME RUNNING\n\n"
	text += "Server: " + str(multiplayer.is_server()) + "\n"
	text += "My ID: " + str(multiplayer.get_unique_id()) + "\n"
	text += "Game Seed: " + str(NetworkManager.game_seed) + "\n"
	text += "Players connected: " + str(NetworkManager.get_player_count()) + "\n"
	
	if selection_manager:
		text += "Selected units: " + str(selection_manager.get_selected_units().size()) + "\n"
	
	text += "\nPlayer List:\n"
	for peer_id in NetworkManager.players:
		var player = NetworkManager.players[peer_id]
		text += "  - " + player.name + " (ID: " + str(peer_id) + ")\n"
	
	text += "\nPress ESC to return to menu"
	text += "\nWASD/Arrows: Pan | Q/E: Rotate | Scroll: Zoom"
	text += "\nLeft Click: Select | Shift+Click: Add | Drag: Box select"
	text += "\nRight Click: Move selected units"
	info_label.text = text
