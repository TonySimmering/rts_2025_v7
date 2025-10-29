extends Node3D

@onready var info_label = $CanvasLayer/InfoLabel

const CAMERA_RIG_SCENE = preload("res://scenes/camera/camera_rig.tscn")
const PRODUCTION_UI_SCENE = preload("res://scripts/ui/production_ui.tscn")
const GAME_UI_SCENE = preload("res://scripts/ui/game_ui.tscn")

var local_camera: Node3D = null
var selection_manager: Node = null
var selection_box: Control = null
var spawn_manager: Node = null
var production_ui: Control = null
var game_ui: Control = null

func _ready():
	print("=== GAME SCENE LOADED ===")
	print("Is Server:", multiplayer.is_server())
	print("My ID:", multiplayer.get_unique_id())
	print("Connected Players:", NetworkManager.players)
	print("Game Seed:", NetworkManager.game_seed)
	
	spawn_local_camera()
	setup_selection_system()
	setup_production_ui()
	await generate_terrain_with_seed()
	setup_spawn_system()
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

func setup_production_ui():
	"""Setup production UI and main game UI"""
	# Main game UI with glass aesthetic
	game_ui = GAME_UI_SCENE.instantiate()
	$CanvasLayer.add_child(game_ui)
	
	# Legacy production UI for building commands
	production_ui = PRODUCTION_UI_SCENE.instantiate()
	$CanvasLayer.add_child(production_ui)
	
	# Connect to selection manager signals
	if selection_manager:
		game_ui.set_selection_manager(selection_manager)
		selection_manager.building_selected.connect(_on_building_selected)
		selection_manager.building_deselected.connect(_on_building_deselected)
	
	print("Game UI and Production UI initialized")

func _on_building_selected(building: Node):
	"""Called when a building is selected"""
	if production_ui:
		production_ui.show_building(building)

func _on_building_deselected():
	"""Called when building selection is cleared"""
	if production_ui:
		production_ui.hide_ui()

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
	_on_all_players_loaded()

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

func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		print("Returning to menu...")
		NetworkManager.disconnect_from_game()
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

func _on_player_joined(peer_id: int, player_info: Dictionary):
	print("Game scene notified: Player joined - ", peer_id)

func _on_player_left(peer_id: int):
	print("Game scene notified: Player left - ", peer_id)
