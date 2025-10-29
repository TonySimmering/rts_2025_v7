extends Node3D

@onready var info_label = $CanvasLayer/InfoLabel

const CAMERA_RIG_SCENE = preload("res://scenes/camera/camera_rig.tscn")
const PRODUCTION_UI_SCENE = preload("res://scripts/ui/production_ui.tscn")

var local_camera: Node3D = null
var selection_manager: Node = null
var selection_box: Control = null
var spawn_manager: Node = null
var production_ui: Control = null

func _ready():
	print("=== GAME SCENE LOADED ===")
	print("Is Server:", multiplayer.is_server())
	print("My ID:", multiplayer.get_unique_id())
	print("Connected Players:", NetworkManager.players)
	print("Game Seed:", NetworkManager.game_seed)
	
	spawn_local_camera()
	setup_selection_system()
	setup_production_ui()
	setup_spawn_system()  # <-- MOVED HERE (was after generate_terrain)
	await generate_terrain_with_seed()
	spawn_town_centers_and_units()
	
	NetworkManager.player_connected.connect(_on_player_joined)
	NetworkManager.player_disconnected.connect(_on_player_left)
	ResourceManager.resources_changed.connect(_on_resources_changed)
	
	# Initialize resources for all players
	for player_id in NetworkManager.players:
		ResourceManager.initialize_player_resources(player_id)
	
	update_info()

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
	"""Setup production UI and connect to selection manager"""
	production_ui = PRODUCTION_UI_SCENE.instantiate()
	$CanvasLayer.add_child(production_ui)
	
	# Connect to selection manager signals
	if selection_manager:
		selection_manager.building_selected.connect(_on_building_selected)
		selection_manager.building_deselected.connect(_on_building_deselected)
	
	print("Production UI initialized")

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

func _on_selection_changed(selected_units: Array):
	print("Selection changed: ", selected_units.size(), " units/buildings selected")
	update_info()

func _on_resources_changed(player_id: int, resources: Dictionary):
	if player_id == multiplayer.get_unique_id():
		update_info()

func generate_terrain_with_seed():
	var terrain = get_node_or_null("Terrain")
	if not terrain or not terrain.has_method("generate_terrain"):
		push_error("Terrain node not found!")
		return
	
	# Get planned Town Center positions BEFORE terrain generation
	if spawn_manager:
		var map_size = Vector2(128, 128)
		var spawn_positions = spawn_manager.get_all_spawn_positions(map_size)
		terrain.set_town_center_spawn_positions(spawn_positions)
	
	await terrain.generate_terrain(NetworkManager.game_seed)
	print("Terrain generation complete, ready for spawning")

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
	var my_id = multiplayer.get_unique_id()
	var my_resources = ResourceManager.get_player_resources(my_id)
	
	var text = "GAME RUNNING\n\n"
	
	# Resources display
	text += "💰 Resources:\n"
	text += "  Gold: " + str(my_resources.get("gold", 0)) + "\n"
	text += "  Wood: " + str(my_resources.get("wood", 0)) + "\n"
	text += "  Stone: " + str(my_resources.get("stone", 0)) + "\n\n"
	
	text += "Server: " + str(multiplayer.is_server()) + "\n"
	text += "My ID: " + str(my_id) + "\n"
	text += "Game Seed: " + str(NetworkManager.game_seed) + "\n"
	text += "Players connected: " + str(NetworkManager.get_player_count()) + "\n"
	
	if selection_manager:
		var selected = selection_manager.get_selected_units()
		var selected_building = selection_manager.get_selected_building()
		
		if selected_building and is_instance_valid(selected_building):
			text += "Selected: " + selected_building.building_name + "\n"
			
			# Show production info for buildings
			if selected_building.has_method("get_queue_size"):
				var prod_queue = selected_building.get_queue_size()
				if prod_queue > 0:
					text += "🏭 Production queue: " + str(prod_queue) + "\n"
					var progress = selected_building.get_production_progress()
					text += "   Progress: " + str(int(progress * 100)) + "%\n"
		elif selected.size() > 0:
			text += "Selected units: " + str(selected.size()) + "\n"
			
			if is_instance_valid(selected[0]):
				var unit = selected[0]
				
				# Show carrying info for workers
				if unit.has_method("get_carried_amount"):
					var carried = unit.get_carried_amount()
					if carried > 0:
						text += "💼 Carrying: " + str(carried) + " resources\n"
				
				# Show command queue
				if unit.has_method("get_command_queue_size"):
					var queue_size = unit.get_command_queue_size()
					if queue_size > 0:
						text += "📋 Queued commands: " + str(queue_size) + "\n"
	
	text += "\nPlayer List:\n"
	for peer_id in NetworkManager.players:
		var player = NetworkManager.players[peer_id]
		text += "  - " + player.name + " (ID: " + str(peer_id) + ")\n"
	
	text += "\nControls:"
	text += "\nWASD/Arrows: Pan | Q/E: Rotate | Scroll: Zoom"
	text += "\nLeft Click: Select | Shift+Click: Add | Drag: Box select"
	text += "\nRight Click: Move (units only) | Right Click Resource: Gather"
	text += "\nSelect Town Center → Use UI to train workers"
	text += "\nShift+Right Click: Queue command"
	text += "\nESC: Return to menu"
	
	info_label.text = text
