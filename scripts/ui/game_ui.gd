extends Control

# References
@onready var top_bar = $TopBar
@onready var bottom_bar = $BottomBar
@onready var debug_text = $DebugText

# Top bar elements - Fixed paths
@onready var gold_label = $TopBar/HBox/ResourcePanel/Resources/GoldRow/Value
@onready var wood_label = $TopBar/HBox/ResourcePanel/Resources/WoodRow/Value
@onready var stone_label = $TopBar/HBox/ResourcePanel/Resources/StoneRow/Value
@onready var population_label = $TopBar/HBox/ResourcePanel/Resources/PopulationRow/Value
@onready var timer_label = $TopBar/HBox/TimerPanel/Time
@onready var menu_button = $TopBar/HBox/MenuButton

# Bottom bar elements - Fixed paths
@onready var portrait_panel = $BottomBar/HBox/PortraitPanel
@onready var command_panel = $BottomBar/HBox/CommandPanel
@onready var minimap_panel = $BottomBar/HBox/MinimapPanel

# Loading screen
@onready var loading_screen = $LoadingScreen
@onready var loading_status_label = $LoadingScreen/CenterContainer/VBox/StatusLabel

# Game timer
var game_time: float = 0.0
var timer_running: bool = false

# References
var selection_manager: Node = null
var resource_manager: Node = null

func _ready():
	# Initially hide until all players loaded
	timer_running = false
	update_timer()
	# Show loading screen by default
	show_loading_screen()
	_connect_resource_signals()
	_refresh_resource_labels()
	call_deferred("_ensure_resource_bindings")

func show_loading_screen(status: String = "Preparing game..."):
	"""Show the loading screen with optional status text"""
	if loading_screen:
		loading_screen.visible = true
		if loading_status_label:
			loading_status_label.text = status

func hide_loading_screen():
	"""Hide the loading screen when game is ready"""
	if loading_screen:
		loading_screen.visible = false

func update_loading_status(status: String):
	"""Update the loading screen status text"""
	if loading_status_label:
		loading_status_label.text = status

func start_timer():
	"""Called when all players are fully loaded"""
	timer_running = true
	game_time = 0.0
	# Hide loading screen when timer starts
	hide_loading_screen()

func _process(delta):
	if timer_running:
		game_time += delta
		update_timer()

	update_debug_info()

func update_timer():
	var minutes = int(game_time) / 60
	var seconds = int(game_time) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]

func _connect_resource_signals():
	resource_manager = get_node_or_null("/root/ResourceManager")
	if not resource_manager:
		return

	if not resource_manager.resources_changed.is_connected(_on_resources_changed):
		resource_manager.resources_changed.connect(_on_resources_changed)
	if not resource_manager.population_changed.is_connected(_on_population_changed):
		resource_manager.population_changed.connect(_on_population_changed)

func _refresh_resource_labels():
	if not resource_manager:
		resource_manager = get_node_or_null("/root/ResourceManager")
	if not resource_manager:
		return

	var player_id = multiplayer.get_unique_id()
	_on_resources_changed(player_id, resource_manager.get_player_resources(player_id))
	var population = resource_manager.get_population(player_id)
	_on_population_changed(player_id, population.get("used", 0), population.get("capacity", 0))

func _on_resources_changed(player_id: int, resources: Dictionary):
	if player_id != multiplayer.get_unique_id():
		return

	gold_label.text = str(resources.get("gold", 0))
	wood_label.text = str(resources.get("wood", 0))
	stone_label.text = str(resources.get("stone", 0))

func _on_population_changed(player_id: int, used: int, capacity: int):
	if player_id != multiplayer.get_unique_id():
		return

	population_label.text = "%d/%d" % [used, capacity]

func _ensure_resource_bindings() -> void:
	if resource_manager:
		return
	await get_tree().process_frame
	_connect_resource_signals()
	_refresh_resource_labels()

func update_debug_info():
	if not selection_manager:
		return
	
	var debug_lines = []
	
	# Selected units info
	var selected_units = selection_manager.get_selected_units()
	if selected_units.size() > 0:
		debug_lines.append("SELECTED UNITS: %d" % selected_units.size())
		
		var unit = selected_units[0]
		if is_instance_valid(unit):
			# Unit state
			if unit.has_method("get_state_name"):
				debug_lines.append("State: %s" % unit.get_state_name())
			
			# Carrying resources
			if unit.has_method("get_carried_amount"):
				var carried = unit.get_carried_amount()
				if carried > 0:
					debug_lines.append("Carrying: %d resources" % carried)
			
			# Command queue
			if unit.has_method("get_command_queue_size"):
				var queue = unit.get_command_queue_size()
				if queue > 0:
					debug_lines.append("Queued commands: %d" % queue)
	
	# Selected building info
	var selected_building = selection_manager.get_selected_building()
	if selected_building and is_instance_valid(selected_building):
		debug_lines.append("SELECTED: %s" % selected_building.building_name)
		
		# Production queue
		if selected_building.has_method("get_queue_size"):
			var queue_size = selected_building.get_queue_size()
			if queue_size > 0:
				debug_lines.append("Production queue: %d" % queue_size)
				var progress = selected_building.get_production_progress()
				debug_lines.append("Progress: %d%%" % int(progress * 100))
	
	debug_text.text = "\n".join(debug_lines)

func set_selection_manager(manager: Node):
	selection_manager = manager

func _on_menu_button_pressed():
	# TODO: Show pause menu with settings, exit, etc.
	get_tree().paused = true
	print("Menu button pressed - implement pause menu")
