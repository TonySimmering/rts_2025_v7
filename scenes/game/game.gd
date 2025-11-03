extends Node3D

@onready var info_label = $CanvasLayer/InfoLabel

const CAMERA_RIG_SCENE = preload("res://scenes/camera/camera_rig.tscn")
const PRODUCTION_UI_SCENE = preload("res://scripts/ui/production_ui.tscn")
const GAME_UI_SCENE = preload("res://scripts/ui/game_ui.tscn")
const COMMAND_PANEL_UI_SCENE = preload("res://scripts/ui/command_panel_ui.tscn")

var local_camera: Node3D = null
var selection_manager: Node = null
var selection_box: Control = null
var spawn_manager: Node = null
var production_ui: Control = null
var game_ui: Control = null
var command_panel_ui: Control = null
var building_placement_manager: BuildingPlacementManager = null
var fog_of_war_overlay: MeshInstance3D = null

func _ready():
	print("=== GAME SCENE LOADED ===")
	print("Is Server:", multiplayer.is_server())
	print("My ID:", multiplayer.get_unique_id())
	print("Connected Players:", NetworkManager.players)
	print("Game Seed:", NetworkManager.game_seed)

	spawn_local_camera()
	setup_selection_system()
	setup_building_placement_system()
	setup_production_ui()
	await generate_terrain_with_seed()
	setup_fog_of_war()
	setup_spawn_system()
	focus_camera_on_player_start()
	spawn_town_centers_and_units()
	
	NetworkManager.player_connected.connect(_on_player_joined)
	NetworkManager.player_disconnected.connect(_on_player_left)
	ResourceManager.resources_changed.connect(_on_resources_changed)
	
	# Initialize resources for all players
	for player_id in NetworkManager.players:
		ResourceManager.initialize_player_resources(player_id)
	
	# Hide old info label since we have new UI
	if info_label:
		info_label.visible = false

func spawn_local_camera():
	local_camera = CAMERA_RIG_SCENE.instantiate()
	add_child(local_camera)

	var terrain = get_node_or_null("Terrain")
	if terrain:
		local_camera.set_terrain(terrain)

	# Set environment for smart DOF system
	var world_env = get_node_or_null("WorldEnvironment")
	if world_env and world_env.environment:
		local_camera.set_environment(world_env.environment)

	print("Local camera spawned for player ", multiplayer.get_unique_id())

func focus_camera_on_player_start():
	"""Focus the camera on the local player's starting position"""
	if not local_camera or not spawn_manager:
		return

	var player_id = multiplayer.get_unique_id()
	var map_size = Vector2(128, 128)

	# Get the spawn position for this player (same logic as spawn_manager)
	var spawn_pos = spawn_manager.get_spawn_location_for_player(player_id, map_size)

	# Focus camera on the spawn position
	local_camera.focus_on_position(spawn_pos)

	print("Camera focused on player ", player_id, " start position: ", spawn_pos)

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

func setup_building_placement_system():
	"""Setup building placement manager"""
	building_placement_manager = BuildingPlacementManager.new()
	add_child(building_placement_manager)

	await get_tree().process_frame

	# Set references
	if local_camera:
		var camera = local_camera.get_node("CameraPivot/Camera3D")
		building_placement_manager.set_camera(camera)

	var terrain = get_node_or_null("Terrain")
	if terrain:
		building_placement_manager.set_terrain(terrain)

	building_placement_manager.set_player_id(multiplayer.get_unique_id())

	print("Building placement system initialized")

func setup_production_ui():
	"""Setup production UI and main game UI"""
	# Main game UI with glass aesthetic
	game_ui = GAME_UI_SCENE.instantiate()
	$CanvasLayer.add_child(game_ui)
	
	# Legacy production UI for building commands
	production_ui = PRODUCTION_UI_SCENE.instantiate()
	$CanvasLayer.add_child(production_ui)

	# Command panel UI for unit commands (building placement)
	command_panel_ui = COMMAND_PANEL_UI_SCENE.instantiate()
	$CanvasLayer.add_child(command_panel_ui)

	# Set building placement manager reference
	if building_placement_manager:
		command_panel_ui.set_building_placement_manager(building_placement_manager)

	# Connect to selection manager signals
	if selection_manager:
		game_ui.set_selection_manager(selection_manager)
		selection_manager.building_selected.connect(_on_building_selected)
		selection_manager.building_deselected.connect(_on_building_deselected)
		selection_manager.selection_changed.connect(_on_units_selected)

		# Connect production UI rally mode signals to selection manager
		if production_ui:
			production_ui.rally_mode_activated.connect(selection_manager.activate_rally_mode)
			production_ui.rally_mode_deactivated.connect(selection_manager.deactivate_rally_mode)

	print("Game UI and Production UI initialized")

func _on_building_selected(building: Node):
	"""Called when a building is selected"""
	if production_ui:
		production_ui.show_building(building)

func _on_building_deselected():
	"""Called when building selection is cleared"""
	if production_ui:
		production_ui.hide_ui()

func _on_units_selected(selected_units: Array):
	"""Called when units are selected"""
	if command_panel_ui:
		if selected_units.size() > 0:
			command_panel_ui.show_units(selected_units)
		else:
			command_panel_ui.hide_ui()

func setup_spawn_system():
	spawn_manager = Node.new()
	spawn_manager.set_script(load("res://scripts/spawn_manager.gd"))
	spawn_manager.terrain = get_node_or_null("Terrain")
	spawn_manager.name = "SpawnManager"
	add_child(spawn_manager)
	print("Spawn system initialized")

func spawn_town_centers_and_units():
	"""Spawn Town Centers and starting units (server only)"""
	if not multiplayer.is_server():
		return

	await get_tree().create_timer(0.5).timeout

	# First spawn Town Centers
	await spawn_manager.spawn_town_centers()

	# Wait for Town Centers to be ready
	await get_tree().create_timer(0.3).timeout

	# Then spawn workers around Town Centers
	var terrain = get_node_or_null("Terrain")
	var map_size = Vector2(128, 128)

	for player_id in NetworkManager.players:
		var spawn_center = spawn_manager.get_spawn_location_for_player(player_id, map_size)
		spawn_manager.spawn_starting_units(player_id, spawn_center)

	# Start game timer after spawning complete
	await get_tree().create_timer(0.5).timeout
	start_game_for_all_players.rpc()

@rpc("authority", "call_local", "reliable")
func start_game_for_all_players():
	"""Called on all clients when spawning is complete"""
	if game_ui:
		game_ui.start_timer()
		print("Game timer started for player ", multiplayer.get_unique_id())

func _on_all_players_loaded():
	"""Called when all players have spawned and are ready"""
	if game_ui:
		game_ui.start_timer()
		print("Game timer started")

func _on_selection_changed(selected_units: Array):
	print("Selection changed: ", selected_units.size(), " units/buildings selected")

func _on_resources_changed(player_id: int, resources: Dictionary):
	# Resources now updated automatically by game_ui
	pass

func generate_terrain_with_seed():
	var terrain = get_node_or_null("Terrain")
	if terrain and terrain.has_method("generate_terrain"):
		await terrain.generate_terrain(NetworkManager.game_seed)
		print("Terrain generation complete, ready for spawning")
	else:
		push_error("Terrain node not found!")

func setup_fog_of_war():
	"""Initialize fog of war system"""
	# Set map dimensions
	var terrain = get_node_or_null("Terrain")
	if terrain:
		FogOfWarManager.set_map_dimensions(128, 128)

	# Initialize fog for all players
	for player_id in NetworkManager.players:
		FogOfWarManager.initialize_player(player_id)

	# Create fog overlay for local player
	var local_player_id = multiplayer.get_unique_id()
	fog_of_war_overlay = MeshInstance3D.new()
	fog_of_war_overlay.set_script(load("res://scripts/fog_of_war_overlay.gd"))
	fog_of_war_overlay.name = "FogOfWarOverlay"
	add_child(fog_of_war_overlay)

	# Configure fog overlay
	fog_of_war_overlay.set_player_id(local_player_id)
	fog_of_war_overlay.set_map_dimensions(128, 128)

	print("Fog of War initialized for player ", local_player_id)

func _process(_delta):
	# Update fog of war
	if FogOfWarManager:
		FogOfWarManager.update_visibility()

	if Input.is_action_just_pressed("ui_cancel"):
		print("Returning to menu...")
		NetworkManager.disconnect_from_game()
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

func _on_player_joined(peer_id: int, player_info: Dictionary):
	print("Game scene notified: Player joined - ", peer_id)

func _on_player_left(peer_id: int):
	print("Game scene notified: Player left - ", peer_id)
